import { ChevronLeft, ChevronRight, Pause, Play, RotateCcw } from "lucide-react";

function CtrlButton({
  onClick,
  title,
  children,
  primary = false,
  disabled = false,
}: {
  onClick: () => void;
  title: string;
  children: React.ReactNode;
  primary?: boolean;
  disabled?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      title={title}
      disabled={disabled}
      className={`flex h-8 items-center justify-center rounded-md px-2.5 transition-colors disabled:opacity-40 ${
        primary
          ? "bg-accent text-white hover:bg-indigo-700"
          : "bg-surface-2 text-ink-2 hover:bg-surface-3"
      }`}
    >
      {children}
    </button>
  );
}

export function DebuggerControls({
  stepIndex,
  total,
  isPlaying,
  onReset,
  onBack,
  onForward,
  onTogglePlay,
}: {
  stepIndex: number;
  total: number;
  isPlaying: boolean;
  onReset: () => void;
  onBack: () => void;
  onForward: () => void;
  onTogglePlay: () => void;
}) {
  return (
    <div className="flex items-center gap-1.5">
      <CtrlButton onClick={onReset} title="Reset (R)" disabled={total === 0}>
        <RotateCcw size={15} />
      </CtrlButton>
      <CtrlButton onClick={onBack} title="Step back (←)" disabled={stepIndex <= 0}>
        <ChevronLeft size={17} />
      </CtrlButton>
      <CtrlButton onClick={onTogglePlay} title="Play / pause (Space)" primary disabled={total === 0}>
        {isPlaying ? <Pause size={15} /> : <Play size={15} />}
      </CtrlButton>
      <CtrlButton
        onClick={onForward}
        title="Step forward (→)"
        disabled={stepIndex >= total - 1}
      >
        <ChevronRight size={17} />
      </CtrlButton>
      <span className="ml-1.5 font-mono text-xs tabular-nums text-ink-2">
        {total === 0 ? "0 / 0" : `${stepIndex + 1} / ${total}`}
      </span>
    </div>
  );
}
