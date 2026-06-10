// FIXTURE — jobs list page (synthetic)
export default function JobsPage({ jobs }: { jobs: Job[] }) {
  return (
    <div>
      <h2>Job Records</h2>
      <button onClick={syncEntities}>Re-sync entities</button>
      {jobs.length === 0 ? (
        <p>No records found in the jobs table.</p>
      ) : (
        <ul>
          {jobs.map((j) => (
            <li key={j.id}>
              {j.customer_display_name} — {j.sched_ts} —
              <a href={`/jobs/${j.id}/dispatch_form`}>Open dispatch_form</a>
              <button onClick={() => hardDelete(j.id)}>Delete</button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
