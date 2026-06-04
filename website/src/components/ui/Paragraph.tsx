import { ReactNode } from "react";
import clsx from "clsx";

/* ---------------- Types ---------------- */

type ParagraphSize = "sm" | "md" | "lg";
type ParagraphAlign = "left" | "center" | "right" | "justify";
type ParagraphWeight = "normal" | "medium" | "semibold";

type ParagraphColor = "base-content" | "primary" | "secondary" | "accent" | "neutral" | "info" | "success" | "warning" | "error";

type ParagraphFont = "space" | "nosifer";

/* ---------------- Props ---------------- */

interface ParagraphProps {
  /** Text size */
  size?: ParagraphSize;

  /** Alignment */
  align?: ParagraphAlign;

  /** Font weight */
  weight?: ParagraphWeight;

  /** Text color */
  color?: ParagraphColor;

  /** Google font */
  font?: ParagraphFont;

  /** Limit width for better reading */
  maxWidth?: boolean;

  /** Extra classes */
  className?: string;

  /** Content */
  children: ReactNode;
}

/* ---------------- Component ---------------- */

export default function Paragraph({
  size = "md",
  align = "left",
  weight = "normal",
  color = "base-content",
  font = "space",
  maxWidth = false,
  className,
  children,
}: ParagraphProps) {
  /* Sizes */
  const sizeClasses: Record<ParagraphSize, string> = {
    sm: "text-sm sm:text-base",
    md: "text-base sm:text-lg",
    lg: "text-lg sm:text-xl",
  };

  /* Weights */
  const weightClasses: Record<ParagraphWeight, string> = {
    normal: "font-normal",
    medium: "font-medium",
    semibold: "font-semibold",
  };

  /* Alignment */
  const alignClasses: Record<ParagraphAlign, string> = {
    left: "text-left",
    center: "text-center",
    right: "text-right",
    justify: "text-justify",
  };

  /* Fonts */
  const fontClasses: Record<ParagraphFont, string> = {
    space: "font-space",
    nosifer: "font-nosifer",
  };

  /* Colors (Tailwind safe) */
  const colorClasses: Record<ParagraphColor, string> = {
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
    <p
      className={clsx(
        "leading-relaxed transition-all duration-300",

        sizeClasses[size],
        weightClasses[weight],
        alignClasses[align],
        fontClasses[font],
        colorClasses[color],

        maxWidth && "max-w-3xl mx-auto",

        className,
      )}
    >
      {children}
    </p>
  );
}
