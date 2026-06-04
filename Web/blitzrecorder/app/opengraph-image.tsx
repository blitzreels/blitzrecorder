import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { ImageResponse } from "next/og";

export const alt =
  "BlitzRecorder — short video, studio quality. Your iPhone is the studio camera for your Mac.";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

const MINT = "#5EF2AF";

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
  const [font, iconData, screenData] = await Promise.all([
    loadDisplayFont(),
    readFile(join(process.cwd(), "app/icon.png")),
    readFile(
      join(process.cwd(), "public/generated-screens/macos-recorder-live.png")
    ),
  ]);
  const icon = `data:image/png;base64,${iconData.toString("base64")}`;
  const screen = `data:image/png;base64,${screenData.toString("base64")}`;
  const fontFamily = font ? "Schibsted Grotesk" : undefined;

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          position: "relative",
          background: "#060709",
          fontFamily,
        }}
      >
        {/* mint spotlight behind the screenshot */}
        <div
          style={{
            position: "absolute",
            top: 0,
            left: 0,
            width: "100%",
            height: "100%",
            background:
              "radial-gradient(ellipse 55% 60% at 78% 45%, rgba(94,242,175,0.20), rgba(94,242,175,0))",
          }}
        />

        {/* Mac screenshot in a dark bezel, bleeding off the right edge */}
        <div
          style={{
            position: "absolute",
            right: -130,
            top: 96,
            display: "flex",
            padding: 12,
            borderRadius: 20,
            background: "#0c0d10",
            border: "1px solid rgba(255,255,255,0.12)",
            transform: "rotate(2deg)",
            boxShadow: "0 50px 120px rgba(0,0,0,0.7)",
          }}
        >
          {/* 1480x1092 source */}
          <img src={screen} alt="" width={560} height={413} style={{ borderRadius: 10 }} />
        </div>

        {/* copy */}
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            justifyContent: "center",
            paddingLeft: 72,
            width: 660,
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
            <span>Short video,</span>
            <span style={{ color: MINT }}>studio quality.</span>
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
            <span>Your iPhone is the studio camera</span>
            <span>for your Mac.</span>
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
