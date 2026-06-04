import { platforms } from ".";
import Button from "@/components/ui/Button";

type Props = {
  open: boolean;
  setOpen: (v: boolean) => void;
  platform?: string;
};

const ComingSoonModal = ({ open, setOpen, platform }: Props) => {
  if (!open) return null;

  const isWindows = platform === "Windows";
  const isLinux = platform === "Linux";

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* overlay */}
      <div className="absolute inset-0 bg-black/70" onClick={() => setOpen(false)} />

      {/* modal */}
      <div className="relative w-[90%] max-w-md rounded-2xl border border-slate-700 bg-slate-900 p-6 text-white shadow-xl">
        <h3 className="text-2xl font-bold text-center">🚧 Coming Soon</h3>

        <p className="text-center text-gray-400 mt-3">
          {platform ? (
            <>
              <span className="text-white font-semibold">{platform}</span> version is under development. We’re working hard to bring it to
              you soon 🚀
            </>
          ) : (
            "This platform is under development. We are working hard to bring it to you soon 🚀"
          )}
        </p>

        {/* Available on info */}
        <div className="mt-6">
          <p className="text-sm text-gray-500 text-center mb-3">Available on</p>

          <div className="flex flex-wrap justify-center gap-2">
            {platforms.map((p) => (
              <div
                key={p.label}
                className={`flex items-center gap-2 px-4 py-2 rounded-lg border text-sm transition-all cursor-pointer
          ${p.isAvailable ? "border-slate-700 bg-slate-800/40 text-gray-100" : "border-dashed border-yellow-500/40 bg-slate-800/20 "}`}
              >
                {p.icon}
                <div className="flex flex-col">
                  <span className="font-medium text-gray-100">{p.label}</span>

                  {!p.isAvailable && <span className="text-xs text-yellow-400">Coming soon</span>}
                </div>
              </div>
            ))}
          </div>
        </div>

        <Button className="mt-6 w-full" onClick={() => setOpen(false)}>
          Got it
        </Button>
      </div>
    </div>
  );
};

export default ComingSoonModal;
