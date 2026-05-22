import type { ExampleManifest } from "../types";

export function ExamplePicker({
  examples,
  current,
  onSelect,
}: {
  examples: ExampleManifest[];
  current: string;
  onSelect: (id: string) => void;
}) {
  return (
    <div className="flex gap-1">
      {examples.map((e) => {
        const active = e.id === current;
        return (
          <button
            key={e.id}
            onClick={() => onSelect(e.id)}
            className={`rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
              active
                ? "bg-accent text-white shadow-sm"
                : "bg-surface-2 text-ink-2 hover:bg-surface-3"
            }`}
          >
            {e.title}
          </button>
        );
      })}
    </div>
  );
}
