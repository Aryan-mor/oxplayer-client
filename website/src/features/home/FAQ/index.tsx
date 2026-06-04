import Container from "@/components/ui/Container";
import Heading from "@/components/ui/Heading";

const faqs = [
  {
    q: "What is OXPlayer?",
    a: "OXPlayer is a Telegram-powered video manager and streaming app that helps you organize, browse, and watch your personal video collection through a beautiful Netflix-style interface.",
  },
  {
    q: "Do I need a Telegram account to use OXPlayer?",
    a: "Yes. OXPlayer requires an active Telegram account for authentication and video management. You can sign in using your Telegram account and connect your personal media library.",
  },
  {
    q: "How do I add movies and videos?",
    a: "Simply send a video or movie file to the OXPlayer Telegram Bot. The bot processes the content, gathers metadata, and automatically adds it to your OXPlayer library when indexing is complete.",
  },
  {
    q: "Does OXPlayer provide movies or TV shows?",
    a: "No. OXPlayer does not host, sell, or distribute any media content. The app only helps you organize and stream videos that you personally upload through Telegram.",
  },
  {
    q: "Can I continue watching from where I left off?",
    a: "Yes. OXPlayer automatically tracks your watch progress and allows you to resume playback from the exact point where you stopped watching.",
  },
  {
    q: "Are my favorites and watchlists synchronized?",
    a: "Yes. Your favorites, watchlists, viewing history, and playback progress are synchronized with your account so you can access them whenever you sign in again.",
  },
  {
    q: "Is my content private and secure?",
    a: "Your library is linked to your personal Telegram account. OXPlayer focuses on providing a secure and personalized viewing experience while keeping your content accessible only to your account.",
  },
  {
    q: "What features does OXPlayer offer?",
    a: "OXPlayer includes a personal media library, rich movie metadata, smart search, favorites, watchlists, subtitle preferences, resume playback, and a modern streaming experience inspired by leading media platforms.",
  },
];

const FAQ = () => {
  return (
    <section className="pt-24 pb-20">
      <Container>
        <div>
          <Heading level="h2" align="center" className="mb-7 !text-gray-100">
            FAQ
          </Heading>

          {/* FAQ List */}
          <div className="max-w-3xl mx-auto space-y-4">
            {faqs.map((item, i) => (
              <div key={i} tabIndex={0} className="collapse collapse-arrow border  bg-slate-900 border-slate-700">
                <div className="collapse-title text-lg font-medium">{item.q}</div>

                <div className="collapse-content">
                  <p className="text-base-content/80">{item.a}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </Container>
    </section>
  );
};

export default FAQ;
