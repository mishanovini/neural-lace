// FIXTURE — settings page (synthetic)
export default function SettingsPage() {
  return (
    <div>
      <h2>Org Configuration</h2>
      <section>
        <h3>Messaging</h3>
        <label>default_reply_window_mins</label>
        <input type="number" defaultValue={30} />
        <button>Upsert config</button>
      </section>
      <section>
        <h3>Danger zone</h3>
        {/* destructive, no confirmation dialog */}
        <button onClick={purgeAllConversations}>Purge</button>
      </section>
      <section>
        <h3>Integrations</h3>
        <p>Configure your SIP trunk and CPaaS BYOC settings below.</p>
        <button>Submit</button>
      </section>
    </div>
  );
}
