import { useEffect, useRef, useState } from "react";
import { Upload } from "lucide-react";
import type { Trace } from "../types";

/** Loads a user-supplied trace via a file picker button in the header *or* by
 * dragging the file anywhere onto the window. Validates that the parsed JSON
 * looks like a Trace (schemaVersion 1, with an events array). */
export function TraceLoader({
  onLoad,
  onError,
}: {
  onLoad: (trace: Trace, label?: string) => void;
  onError: (msg: string) => void;
}) {
  const fileInput = useRef<HTMLInputElement | null>(null);
  const [dragging, setDragging] = useState(false);

  // Whole-window drag-and-drop. We count dragenter/dragleave so the overlay
  // doesn't flicker as the cursor moves between child elements.
  useEffect(() => {
    let depth = 0;
    const onEnter = (e: DragEvent) => {
      if (!e.dataTransfer?.types?.includes("Files")) return;
      depth += 1;
      setDragging(true);
    };
    const onLeave = () => {
      depth = Math.max(0, depth - 1);
      if (depth === 0) setDragging(false);
    };
    const onOver = (e: DragEvent) => {
      if (e.dataTransfer?.types?.includes("Files")) e.preventDefault();
    };
    const onDrop = (e: DragEvent) => {
      depth = 0;
      setDragging(false);
      if (!e.dataTransfer?.files?.length) return;
      e.preventDefault();
      handleFile(e.dataTransfer.files[0]);
    };
    window.addEventListener("dragenter", onEnter);
    window.addEventListener("dragleave", onLeave);
    window.addEventListener("dragover", onOver);
    window.addEventListener("drop", onDrop);
    return () => {
      window.removeEventListener("dragenter", onEnter);
      window.removeEventListener("dragleave", onLeave);
      window.removeEventListener("dragover", onOver);
      window.removeEventListener("drop", onDrop);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function handleFile(file: File) {
    try {
      const text = await file.text();
      const data = JSON.parse(text);
      if (typeof data !== "object" || data === null || !Array.isArray(data.events)) {
        throw new Error("not a Mooncake trace JSON (missing `events` array)");
      }
      onLoad(data as Trace, file.name);
    } catch (e) {
      onError((e as Error).message);
    }
  }

  return (
    <>
      <button
        onClick={() => fileInput.current?.click()}
        title="Load a trace JSON file"
        className="flex items-center gap-1 rounded border border-border-subtle bg-surface-2 px-2 py-1 text-[11px] text-ink-2 hover:bg-surface-3"
      >
        <Upload size={11} />
        Load trace…
      </button>
      <input
        ref={fileInput}
        type="file"
        accept="application/json,.json"
        className="hidden"
        onChange={(e) => {
          const f = e.target.files?.[0];
          if (f) handleFile(f);
          e.target.value = "";
        }}
      />
      {dragging && (
        <div className="pointer-events-none fixed inset-0 z-50 flex items-center justify-center bg-accent/10 backdrop-blur-sm">
          <div className="rounded-lg border-2 border-dashed border-accent bg-surface-1 px-6 py-4 text-sm font-medium text-accent">
            Drop a trace JSON to load it
          </div>
        </div>
      )}
    </>
  );
}
