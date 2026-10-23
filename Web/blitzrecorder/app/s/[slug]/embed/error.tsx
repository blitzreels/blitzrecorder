"use client";

import styles from "./embed.module.css";

export default function EmbedError({ retry }: { error: Error & { digest?: string }; retry: () => void }) {
  return <main className={styles.frame}>
    <div className={styles.unavailable}>
      <p>This video couldn’t load.</p>
      <button type="button" onClick={retry}>Try again</button>
    </div>
  </main>;
}
