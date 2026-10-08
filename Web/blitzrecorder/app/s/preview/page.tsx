import { notFound } from "next/navigation";
import { shareDetails, type TranscriptCue, type VideoDetails } from "@/lib/hosting/details";
import { SharedVideoView } from "../[slug]/shared-video-view";

const DURATION = 30.3;

/** Local fixture so the share layout can be opened without a hosted asset. */
const LINES: [number, string, string][] = [
  [18, "Alex", "On reprend le pricing de l’offre annuelle et le plafond du bonus."],
  [46, "Sam", "Ouais."],
  [74, "Jordan", "Le cap à deux cents dollars tient jusqu’à quarante mille vues, après on coupe."],
  [210, "Alex", "Ok."],
  [248, "Sam", "Chaque créateur validé touche le même montant, les vues ne changent pas le fixe."],
  [400, "Alex", "Les comptes sans historique restent à sept jours pour poster, pas quinze."],
  [470, "Jordan", "D’accord."],
  [530, "Sam", "On laisse TikTok, Instagram, YouTube et X ouverts, sauf si la marque demande moins."],
  [760, "Alex", "Le suivi des vues part le jour où la vidéo est envoyée, pendant dix jours."],
  [840, "Sam", "Ouais ouais."],
  [910, "Jordan", "Une vidéo doit faire mille vues vérifiées en quarante-huit heures, sinon l’entrée saute."],
  [1100, "Sam", "Le brief doit dire comment le créateur ouvre le produit, sinon les vidéos seront vides."],
  [1180, "Alex", "Exactement."],
  [1260, "Jordan", "On propose un code d’accès limité plutôt qu’un essai illimité."],
  [1420, "Alex", "L’argent part seulement quand la vidéo est approuvée, le reste reste dans le wallet."],
  [1510, "Sam", "Merci."],
  [1580, "Jordan", "Un retrait renvoie le hold tout de suite, ce n’est pas un remboursement carte."],
  [1760, "Sam", "On verrouille le brief et la récompense au lancement, le budget peut seulement monter."],
  [1840, "Alex", "Ouais."],
  [1900, "Jordan", "Prochaine étape : relire le brouillon, puis activer seulement après un oui séparé."],
];

function fixture(): VideoDetails {
  const transcript: TranscriptCue[] = LINES.map(([start, speaker, text]) => {
    const at = Math.round((start / 1900) * 26 * 10) / 10;
    return { start: at, end: Math.min(DURATION, at + 1.4), text, speaker };
  });
  const chapters = ["Pricing", "Bonus cap", "Fixed fee", "New accounts", "Platforms", "Tracking", "Brief", "Next steps"]
    .map((title, index) => ({ start: index * 3.6, title, summary: null }));
  return { version: 1, summary: null, language: "fr", recordedAt: "2026-09-12T15:04:00.000Z", transcript, chapters };
}

export default function SharePreviewPage() {
  if (process.env.NODE_ENV === "production") notFound();
  return <SharedVideoView slug="preview" source="/videos/presentation.mp4" poster="/media/presentation-poster.webp"
    title="Pricing review — annual plan" width={1920} height={1080} duration={DURATION} frameRate={60}
    details={shareDetails({ details: fixture(), duration: DURATION })} viewer={null} />;
}
