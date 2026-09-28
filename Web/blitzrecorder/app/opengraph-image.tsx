import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { ImageResponse } from "next/og";

export const alt =
  "BlitzRecorder. Record and edit on your Mac. Free and open source.";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

const MINT = "#17FFA6";

/**
 * Brand display font, fetched once at build time (the OG image is statically
 * generated). Returns null offline so the image still renders with the
 * default font instead of failing the build.
 */
async function loadDisplayFont(): Promise<ArrayBuffer | null> {
  try {
    const css = await (
      await fetch(
        "https://fonts.googleapis.com/css2?family=Schibsted+Grotesk:wght@800"
      )
    ).text();
    const url = css.match(
      /src: url\((.+?)\) format\('(?:opentype|truetype)'\)/
    )?.[1];
    if (!url) return null;
    return await (await fetch(url)).arrayBuffer();
  } catch {
    return null;
  }
}

export default async function OpengraphImage() {
  const [font, iconData] = await Promise.all([
    loadDisplayFont(),
    readFile(join(process.cwd(), "app/icon.png")),
  ]);
  const icon = `data:image/png;base64,${iconData.toString("base64")}`;
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          position: "relative",
          background: "#060709",
          ...(font ? { fontFamily: "Schibsted Grotesk" } : {}),
        }}
      >
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            justifyContent: "center",
            paddingLeft: 72,
            width: 1100,
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: 22 }}>
            <img src={icon} alt="" width={76} height={76} style={{ borderRadius: 17 }} />
            <span style={{ fontSize: 42, fontWeight: 800, color: "#fff" }}>
              BlitzRecorder
            </span>
          </div>
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              marginTop: 52,
              fontSize: 82,
              lineHeight: 1.0,
              fontWeight: 800,
              letterSpacing: "-3px",
              color: "#fff",
            }}
          >
            <span>Record and edit videos</span>
            <span style={{ color: MINT }}>on your Mac.</span>
          </div>
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              marginTop: 36,
              fontSize: 30,
              lineHeight: 1.35,
              color: "rgba(232,242,238,0.74)",
            }}
          >
            <span>Screen and camera in one take.</span>
            <span>Free and open source.</span>
          </div>
        </div>
      </div>
    ),
    {
      ...size,
      fonts: font
        ? [{ name: "Schibsted Grotesk", data: font, weight: 800, style: "normal" }]
        : undefined,
    }
  );
}
