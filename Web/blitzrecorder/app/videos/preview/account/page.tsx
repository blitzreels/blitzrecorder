import { AccountPanel } from "@/components/hosting/app-panels";
import { PageHeader } from "@/components/hosting/app-shell";
import { previewOverview } from "../links";

export default function AccountPreview() {
  return <>
    <PageHeader title="Account" description="Your sign-in and the devices connected to it." actions={null} />
    <AccountPanel overview={previewOverview} mode="preview" />
  </>;
}
