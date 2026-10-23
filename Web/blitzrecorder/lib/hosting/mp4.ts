/** Reads `length` bytes at `offset`, or fewer at the end of the file. */
export type RangeReader = (range: { offset: number; length: number }) => Promise<Buffer>;

/** What an MP4's header says about it: the longest of the movie and track durations, and the largest track size. */
export type Mp4Facts = { duration: number; width: number; height: number };

const HEADER_BYTES = 16;
const MAX_MOOV_BYTES = 64 * 1024 * 1024;
/** Real files have a handful of top-level boxes (ftyp, free, mdat, moov); a file of tiny junk boxes stops here. */
const MAX_TOP_LEVEL_BOXES = 64;

type Box = { type: string; start: number; body: number; end: number };

function boxAt({ data, at, end }: { data: Buffer; at: number; end: number }): Box | null {
  if (at + 8 > end) return null;
  const small = data.readUInt32BE(at);
  const type = data.toString("latin1", at + 4, at + 8);
  let size = small;
  let header = 8;
  if (small === 1) {
    if (at + 16 > end) return null;
    size = Number(data.readBigUInt64BE(at + 8));
    header = 16;
  }
  if (!Number.isSafeInteger(size) || size < header || at + size > end) return null;
  return { type, start: at, body: at + header, end: at + size };
}

function children({ data, box }: { data: Buffer; box: Box }): Box[] | null {
  const found: Box[] = [];
  for (let at = box.body; at < box.end;) {
    const child = boxAt({ data, at, end: box.end });
    if (!child) return null;
    found.push(child);
    at = child.end;
  }
  return found;
}

/** `mvhd` and `mdhd` share their layout up to the duration. */
function headerDuration({ data, box }: { data: Buffer; box: Box }): number | null {
  if (box.end - box.body < 32) return null;
  const version = data.readUInt8(box.body);
  const timescale = data.readUInt32BE(box.body + (version === 1 ? 20 : 12));
  const duration = version === 1 ? Number(data.readBigUInt64BE(box.body + 24)) : data.readUInt32BE(box.body + 16);
  return timescale > 0 ? duration / timescale : null;
}

function moovFacts(moov: Buffer): Mp4Facts | null {
  const root = boxAt({ data: moov, at: 0, end: moov.length });
  const boxes = root && children({ data: moov, box: root });
  if (!boxes) return null;
  const mvhd = boxes.find((box) => box.type === "mvhd");
  let duration = mvhd ? headerDuration({ data: moov, box: mvhd }) ?? 0 : 0;
  let width = 0;
  let height = 0;
  for (const trak of boxes.filter((box) => box.type === "trak")) {
    const parts = children({ data: moov, box: trak });
    if (!parts) return null;
    const tkhd = parts.find((box) => box.type === "tkhd");
    // Width and height close every tkhd, as 16.16 fixed point; audio tracks report zero.
    if (tkhd && tkhd.end - tkhd.body >= 8) {
      width = Math.max(width, moov.readUInt32BE(tkhd.end - 8) / 65536);
      height = Math.max(height, moov.readUInt32BE(tkhd.end - 4) / 65536);
    }
    const mdia = parts.find((box) => box.type === "mdia");
    const mdhd = mdia && children({ data: moov, box: mdia })?.find((box) => box.type === "mdhd");
    if (mdhd) duration = Math.max(duration, headerDuration({ data: moov, box: mdhd }) ?? 0);
  }
  return duration > 0 ? { duration, width, height } : null;
}

/**
 * Duration and size from an MP4's `moov`, read with a few small range requests: the top-level boxes are walked by
 * their headers, so a `moov` after gigabytes of media costs one more request, not a download. Null when the file
 * is not an MP4 this can read.
 */
export async function mp4Facts({ read, bytes }: { read: RangeReader; bytes: number }): Promise<Mp4Facts | null> {
  let offset = 0;
  for (let count = 0; count < MAX_TOP_LEVEL_BOXES && offset + 8 <= bytes; count++) {
    const box = declaredBox(await read({ offset, length: HEADER_BYTES }));
    if (!box || box.size > bytes - offset) return null;
    if (box.type === "moov") return box.size > MAX_MOOV_BYTES ? null : moovFacts(await read({ offset, length: box.size }));
    offset += box.size;
  }
  return null;
}

/** A top-level box's type and full size from its first bytes, before the rest of it is read. */
function declaredBox(header: Buffer): { type: string; size: number } | null {
  if (header.length < 8) return null;
  const small = header.readUInt32BE(0);
  const size = small !== 1 ? small : header.length >= 16 ? Number(header.readBigUInt64BE(8)) : Number.NaN;
  return Number.isSafeInteger(size) && size >= 8 ? { type: header.toString("latin1", 4, 8), size } : null;
}
