import { ElementType, ReactNode } from "react";
import clsx from "clsx";

/* ---------------- Types ---------------- */

type HeadingLevel = "h1" | "h2" | "h3" | "h4" | "h5" | "h6";

type HeadingSize = "sm" | "md" | "lg" | "xl" | "2xl";

type HeadingAlign = "left" | "center" | "right";

type HeadingWeight = "normal" | "medium" | "semibold" | "bold";

type HeadingSpacing = "tight" | "normal" | "wide";

/* DaisyUI colors */
type HeadingColor = "base-content" | "primary" | "secondary" | "accent" | "neutral" | "info" | "success" | "warning" | "error";

/* Font options */
type HeadingFont = "nosifer" | "space";

/* ---------------- Props ---------------- */

interface HeadingProps {
  level?: HeadingLevel;
  size?: HeadingSize;
  color?: HeadingColor;
  align?: HeadingAlign;
  weight?: HeadingWeight;
  spacing?: HeadingSpacing;
  underline?: boolean;

  /** Select Google Font */
  font?: HeadingFont;

  className?: string;
  children: ReactNode;
}

/* ---------------- Component ---------------- */

export default function Heading({
  level = "h1",
  size = "xl",
  color = "base-content",
  align = "left",
  weight = "bold",
  spacing = "tight",
  underline = false,
  font = "space", // Default font
  className,
  children,
}: HeadingProps) {
  const Tag: ElementType = level;

  /* Responsive sizes */
  const sizeClasses: Record<HeadingSize, string> = {
    sm: "text-base sm:text-lg",
    md: "text-lg sm:text-xl md:text-2xl",
    lg: "text-xl sm:text-2xl md:text-3xl",
    xl: "text-2xl sm:text-3xl md:text-4xl lg:text-5xl lg:leading-20",
    "2xl": "text-3xl sm:text-4xl md:text-5xl lg:text-6xl",
  };

  /* Font weight */
  const weightClasses: Record<HeadingWeight, string> = {
    normal: "font-normal",
    medium: "font-medium",
    semibold: "font-semibold",
    bold: "font-bold",
  };

  /* Letter spacing */
  const spacingClasses: Record<HeadingSpacing, string> = {
    tight: "tracking-tight",
    normal: "tracking-normal",
    wide: "tracking-wide",
  };

  /* Alignment */
  const alignClasses: Record<HeadingAlign, string> = {
    left: "text-left",
    center: "text-center",
    right: "text-right",
  };

  /* Fonts */
  const fontClasses: Record<HeadingFont, string> = {
    nosifer: "font-nosifer",
    space: "font-space",
  };

  /* Colors (safe for Tailwind purge) */
  const colorClasses: Record<HeadingColor, string> = {
    "base-content": "text-base-content",
    primary: "text-primary",
    secondary: "text-secondary",
    accent: "text-accent",
    neutral: "text-neutral",
    info: "text-info",
    success: "text-success",
    warning: "text-warning",
    error: "text-error",
  };

  return (
    <Tag
      className={clsx(
        "leading-tight transition-all duration-300 text-primary",

        sizeClasses[size],
        weightClasses[weight],
        spacingClasses[spacing],
        alignClasses[align],
        fontClasses[font],
        colorClasses[color],

        underline && "border-b-2 border-primary inline-block pb-1",

        className,
      )}
    >
      {children}
    </Tag>
  );
}
