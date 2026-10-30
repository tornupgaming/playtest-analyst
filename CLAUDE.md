# Playtest Analyst

An AI UX researcher for solo game developers, built for the **Meta Global AI Developer Hackathon** (Cerebral Valley, Indie developer track).

A Godot 4.7 plugin that records a playtest (screen, think-aloud and telemetry), sends it to Muse Wonder for analysis, and proposes fixes. The plugin is `addons/playtest_analyst/`; the Godot project that hosts it is `sample_game/`, whose `addons/playtest_analyst` is a symlink to it. Run Godot with `--path sample_game`. See `README.md` for the layout.

## The event

* **Format:** Remote, 10 days, $1M prize pool across two tracks.
* **Dates:** Kickoff Oct 26 (livestream \~5pm UK). Workshops and Discord office hours Oct 27 – Nov 4. Judging Nov 4–8. Finals and winners Nov 9.
* **Submission deadline:** Nov 4, 9:00 PM ET = **2:00 AM UK, Thu Nov 5**. US clocks change on Nov 1. Our target is Wednesday evening UK time.
* **Track:** Indie developer, judged on **creativity, technical ambition, and whether it works**.
* **Theme:** "Build for Your World", which means solving a problem you know firsthand.
* **Available models:** Muse Spark series, Muse Wonder, Muse Image and SAM 3.1 via the Meta Model API; Meta open-weights models (credits from Baseten, Modal and Fireworks); the Muse Code coding agent.
* **Official rules** were due before kickoff. Read them before building ([TUG-88](https://linear.app/tornupgaming/issue/TUG-88/read-official-rules-and-submission-requirements)), especially on pre-existing code and assets.

Event page: [https://cerebralvalley.ai/e/meta-ai-developer-hackathon](<https://cerebralvalley.ai/e/meta-ai-developer-hackathon>)

## The problem

Solo and indie game developers can't afford playtest analysts or UX researchers. The usual workflow is to record a friend playing the build, then spend hours scrubbing footage to find where they got confused, bored or stuck. In practice, much of that footage never gets properly reviewed.

## What we're building

A Godot plugin and analysis pipeline that turns a raw playtest session into actionable design feedback.

1. **Record.** The plugin captures a playtest session:
   * screen video;
   * mic audio of the player thinking aloud;
   * a structured telemetry event log (deaths, retries, time per zone, input idle periods, UI opens, objective updates).
2. **Analyse.** **Muse Wonder** takes the video, audio and telemetry together and produces a timestamped friction report. It covers:
   * confusion moments matched against think-aloud audio;
   * difficulty spikes;
   * pacing problems;
   * UI issues.
3. **Annotate.** **SAM 3.1** segments the relevant UI element or game object in each finding's key frame. Each finding then comes with an annotated screenshot, for example "the player looked here; the quest marker was here".
4. **Fix.** *(Stretch goal.)* An agent proposes concrete GDScript or `.tres` diffs, such as tuning values, tooltip text, spawn timing or UI contrast. You can apply them with one click in the editor.
5. **Remember.** *(Stretch goal.)* Each build's report is compared with the previous one. Findings are tagged **resolved**, **new** or **persisting**, which uses Muse Wonder's memory and long-context strengths.

## Wiki: what we know

`docs/wiki/` holds the facts we've established about the APIs, tools and platforms we depend on, each with a source (vendor docs or our own measured runs).

- **Before** researching an API, a limit, a price or a platform behaviour, read `docs/wiki/index.md`. The answer may already be there.
- **After** a spike, a measured run or reading new docs, ingest what you learned into the wiki. Follow `docs/wiki/CLAUDE.md`: facts only, each one sourced, with no hypotheses or plans.
