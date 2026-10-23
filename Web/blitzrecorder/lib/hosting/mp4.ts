/** Reads `length` bytes at `offset`, or fewer at the end of the file. */
export type RangeReader = (range: { offset: number; length: number }) => Promise<Buffer>;

const HEADER_BYTES = 16;
const MAX_MOOV_BYTES = 64 * 1024 * 1024;

function boxHeader({ data, at }: { data: Buffer; at: number }): { type: string; size: number; header: number } | null {
  if (data.length < at + 8) return null;
  const small = data.readUInt32BE(at);
  const type = data.toString("latin1", at + 4, at + 8);
  if (small === 1) {
    if (data.length < at + 16) return null;
    const size = Number(data.readBigUInt64BE(at + 8));
    return Number.isSafeInteger(size) ? { type, size, header: 16 } : null;
  }
  return small >= 8 ? { type, size: small, header: 8 } : null;
}

/**
 * The movie duration in seconds from an MP4's `moov/mvhd` box, read with a few small range requests: the top-level
 * boxes are walked by their headers, so a `moov` after gigabytes of media costs one more request, not a download.
 * Null when the file is not an MP4 this can read.
 */
export async function mp4Duration({ read, bytes }: { read: RangeReader; bytes: number }): Promise<number | null> {
  let offset = 0;
  while (offset + 8 <= bytes) {
    const box = boxHeader({ data: await read({ offset, length: HEADER_BYTES }), at: 0 });
    if (!box || box.size > bytes - offset) return null;
    if (box.type === "moov") {
      if (box.size > MAX_MOOV_BYTES) return null;
      return movieDuration(await read({ offset: offset + box.header, length: box.size - box.header }));
    }
    offset += box.size;
  }
  return null;
}

function movieDuration(moov: Buffer): number | null {
  let at = 0;
  while (at + 8 <= moov.length) {
    const box = boxHeader({ data: moov, at });
    if (!box || at + box.size > moov.length) return null;
    if (box.type === "mvhd") {
      if (box.size < box.header + 32) return null;
      const body = at + box.header;
      const version = moov.readUInt8(body);
      const timescale = version === 1 ? moov.readUInt32BE(body + 20) : moov.readUInt32BE(body + 12);
      const duration = version === 1 ? Number(moov.readBigUInt64BE(body + 24)) : moov.readUInt32BE(body + 16);
      return timescale > 0 && duration > 0 ? duration / timescale : null;
    }
    at += box.size;
  }
  return null;
}
