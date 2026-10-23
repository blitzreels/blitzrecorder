import { TRY_URL } from "../try-url";
import styles from "./embed.module.css";

/** Posts keep their player after a video is removed, so this must read well inside a small frame. */
export default function UnavailableEmbed() {
  return <main className={styles.frame}>
    <div className={styles.unavailable}>
      <p>This video is no longer available.</p>
      <a href={TRY_URL} target="_blank" rel="noopener">Made with BlitzRecorder</a>
    </div>
  </main>;
}
