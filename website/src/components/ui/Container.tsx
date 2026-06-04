import { ReactNode } from "react";
import clsx from "clsx";

interface ContainerProps {
  children: ReactNode;
  className?: string;
}

/**
 * Responsive Container Wrapper
 * Adjusts max-width automatically per Tailwind breakpoints
 */
export default function Container({ children, className }: ContainerProps) {
  return (
    <div
      className={clsx("w-full mx-auto px-4 sm:px-6 lg:px-8 2xl:px-16", "sm:max-w-[640px] md:max-w-[768px] lg:max-w-[1024px] xl:max-w-[1280px] 2xl:max-w-[1536px]", className)}
    >
      {children}
    </div>
  );
}
