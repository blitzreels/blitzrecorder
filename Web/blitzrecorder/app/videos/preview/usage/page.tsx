import { UsagePanel } from "@/components/hosting/app-panels";
import { PageHeader } from "@/components/hosting/app-shell";
import { previewOverview } from "../links";

export default function UsagePreview() {
  return <>
    <PageHeader title="Usage" description="Storage and uploads on BlitzRecorder hosting." actions={null} />
    <UsagePanel overview={previewOverview} />
  </>;
}
