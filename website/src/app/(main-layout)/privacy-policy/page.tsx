import type { Metadata } from "next";
import PrivacyPolicyPage from "@/features/legal/PrivacyPolicyPage";

export const metadata: Metadata = {
  title: "Privacy Policy — OXPlayer",
  description: "How OXPlayer handles your data when you use the Telegram-connected media library app.",
};

export default function Page() {
  return <PrivacyPolicyPage />;
}
