import Container from "@/components/ui/Container";
import Heading from "@/components/ui/Heading";
import { FaIntercom } from "react-icons/fa";
import { GiFiles, GiVibratingSmartphone } from "react-icons/gi";
import { IoPlayBack, IoPlaySkipBackSharp } from "react-icons/io5";
import { MdBlock } from "react-icons/md";
import { SlOrganization } from "react-icons/sl";

const WhyOX = () => {
  return (
    <section className="relative pt-24 md:pt-40">
      <Container>
        <Heading align="center" className="!text-gray-100 mb-10">
          Why OXPlayer
        </Heading>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-5 relative">
          <div className="absolute left-1/2 top-[45%] md:top-1/2 flex h-20 w-20 md:h-20 md:w-20 xl:h-24 xl:w-24 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full bg-gradient-to-r from-primary to-secondary">
            <Heading className="!text-black">VS</Heading>
          </div>

          <div className="bg-slate-900/70 border border-slate-700 p-10 sm:p-20 md:p-12 lg:p-20">
            <Heading level="h5" size="lg" align="center" className="!text-gray-100">
              Traditional Telegram
            </Heading>

            <ul className="space-y-5 mt-10">
              <li>
                <div className="flex gap-5 items-center">
                  <div className="bg-slate-900 rounded-xl border border-slate-700 w-fit p-3">
                    <GiFiles className="!text-gray-400 text-4xl sm:text-5xl" />
                  </div>

                  <Heading level="h4" size="md" className="!text-gray-400 font-medium">
                    Scattered Files
                  </Heading>
                </div>
              </li>
              <li>
                <div className="flex gap-5 items-center">
                  <div className="bg-slate-900 rounded-xl border border-slate-700 w-fit p-3">
                    <MdBlock className="!text-gray-400 text-4xl sm:text-5xl" />
                  </div>

                  <Heading level="h4" size="md" className="!text-gray-400 font-medium">
                    No Organization
                  </Heading>
                </div>
              </li>
              <li>
                <div className="flex gap-5 items-center">
                  <div className="bg-slate-900 rounded-xl border border-slate-700 w-fit p-3">
                    <IoPlaySkipBackSharp className="!text-gray-400 text-4xl sm:text-5xl" />
                  </div>

                  <Heading level="h4" size="md" className="!text-gray-400 font-medium">
                    Basic Playback
                  </Heading>
                </div>
              </li>
            </ul>
          </div>
          <div
            className="bg-slate-900/70 border  p-10 sm:p-20 md:p-12 lg:p-20 rounded-xl"
            style={{
              borderImage: "linear-gradient(to right, var(--color-primary), #FF6900, var(--color-secondary)) 1",
            }}
          >
            <Heading
              level="h5"
              size="lg"
              align="center"
              className="bg-gradient-to-r from-primary to-secondary bg-clip-text text-transparent"
            >
              OXPlayer Experience
            </Heading>

            <ul className="space-y-5 mt-10">
              <li>
                <div className="flex gap-5 items-center">
                  <div
                    className="bg-slate-900 rounded-xl border  w-fit p-3"
                    style={{
                      borderImage: "linear-gradient(to right, var(--color-primary), #FF6900, var(--color-secondary)) 1",
                    }}
                  >
                    <FaIntercom className="!text-primary text-4xl sm:text-5xl" />
                  </div>

                  <Heading
                    level="h4"
                    size="md"
                    className="bg-gradient-to-r from-primary to-secondary bg-clip-text text-transparent font-medium"
                  >
                    Beautiful Netflix Style Interface
                  </Heading>
                </div>
              </li>
              <li>
                <div className="flex gap-5 items-center">
                  <div
                    className="bg-slate-900 rounded-xl border w-fit p-3"
                    style={{
                      borderImage: "linear-gradient(to right, var(--color-primary), #FF6900, var(--color-secondary)) 1",
                    }}
                  >
                    <SlOrganization className="!text-primary text-4xl sm:text-5xl" />
                  </div>

                  <Heading
                    level="h4"
                    size="md"
                    className="bg-gradient-to-r from-primary to-secondary bg-clip-text text-transparent font-medium"
                  >
                    Organized library
                  </Heading>
                </div>
              </li>
              <li>
                <div className="flex gap-5 items-center">
                  <div
                    className="bg-slate-900 rounded-xl border w-fit p-3"
                    style={{
                      borderImage: "linear-gradient(to right, var(--color-primary), #FF6900, var(--color-secondary)) 1",
                    }}
                  >
                    <IoPlayBack className="!text-primary text-4xl sm:text-5xl" />
                  </div>

                  <Heading
                    level="h4"
                    size="md"
                    className="bg-gradient-to-r from-primary to-secondary bg-clip-text text-transparent font-medium"
                  >
                    Advance Playback
                  </Heading>
                </div>
              </li>
              <li>
                <div className="flex gap-5 items-center">
                  <div
                    className="bg-slate-900 rounded-xl border  w-fit p-3"
                    style={{
                      borderImage: "linear-gradient(to right, var(--color-primary), #FF6900, var(--color-secondary)) 1",
                    }}
                  >
                    <GiVibratingSmartphone className="!text-primary text-4xl sm:text-5xl" />
                  </div>

                  <Heading
                    level="h4"
                    size="md"
                    className="bg-gradient-to-r from-primary to-secondary bg-clip-text text-transparent font-medium"
                  >
                    Smart Features
                  </Heading>
                </div>
              </li>
            </ul>
          </div>
        </div>
      </Container>
    </section>
  );
};

export default WhyOX;
