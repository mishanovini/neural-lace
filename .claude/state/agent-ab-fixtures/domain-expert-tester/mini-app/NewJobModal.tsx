// FIXTURE — create-job modal (synthetic). Save path has a silent failure: onSave
// swallows the rejected promise; modal closes whether or not the POST succeeded.
export function NewJobModal({ onClose }: { onClose: () => void }) {
  async function onSave(form: FormData) {
    fetch("/api/jobs", { method: "POST", body: form }).catch(() => {});
    onClose(); // closes immediately; no success/error feedback
  }
  return (
    <form action={onSave}>
      <label>Customer UUID</label>
      <input name="customer_id" />
      <label>Job window start (ISO-8601)</label>
      <input name="sched_ts" />
      <button type="submit">Persist</button>
    </form>
  );
}
