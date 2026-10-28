# Experiments

Each folder here is one small, throwaway experiment we ran before building something, to answer one question with a real measurement instead of a guess. They are kept because they are the evidence behind [DECISIONS.md](../DECISIONS.md). The facts they established are written up, with links back here, in the [wiki](../docs/wiki/index.md).

The code in these folders is not part of the product and isn't maintained. Folder names are our ticket numbers.

| Folder | Question it answered | Where the conclusion lives |
|---|---|---|
| [`tug-93/`](tug-93/) | How should we send a playtest to Muse Wonder (video, audio, transcript), and how accurate are its timestamps? Answer: silent video at 1 fps plus a transcript from Meta's speech-to-text. | [FINDINGS.md](tug-93/FINDINGS.md), [DECISIONS.md §4](../DECISIONS.md#4-model-input), wiki: [Muse Wonder video](../docs/wiki/muse-wonder-video.md), [Meta ASR](../docs/wiki/meta-asr.md) |
| [`tug-94/`](tug-94/) | Can SAM 3.1 find things like a sign, an enemy or a beacon in frames from our test level? | [FINDINGS.md](tug-94/FINDINGS.md), [DECISIONS.md §5](../DECISIONS.md#5-sam-31-under-evaluation), wiki: [SAM 3.1](../docs/wiki/sam-3-1.md) |
| [`tug-95/`](tug-95/) | Can Godot record the screen, the microphone and gameplay events so they line up on one clock? Answer: yes, but record the mic with ffmpeg. | [README.md](tug-95/README.md), [DECISIONS.md §3](../DECISIONS.md#3-capture), wiki: [capture sync](../docs/wiki/capture-sync.md) |
| [`tug-99/`](tug-99/) | Do the first real analysis runs work, and do the recorded video and mic line up after the recording is tidied up? | wiki: [Muse Wonder video](../docs/wiki/muse-wonder-video.md#40-second-session-through-playtest-analyse), [capture sync](../docs/wiki/capture-sync.md) |
| [`tug-104/`](tug-104/) | Does SAM still find the same things in frames cut from the compressed session video, rather than clean screenshots? | wiki: [SAM 3.1, key frames](../docs/wiki/sam-3-1.md#key-frames-from-a-finalized-video-tug-104) |
| [`tug-107/`](tug-107/) | Can Muse Spark write small fixes (patches) for a report's findings that apply cleanly to the game? | [README.md](tug-107/README.md), [DECISIONS.md §8](../DECISIONS.md#8-patches), wiki: [Muse Spark](../docs/wiki/muse-spark.md), [git apply](../docs/wiki/git-apply.md) |
| [`tug-108/`](tug-108/) | Can the editor dock apply and undo one fix while its neighbours stay applied, and how does Godot run outside programs? | [README.md](tug-108/README.md), wiki: [git apply](../docs/wiki/git-apply.md), [running processes from Godot](../docs/wiki/godot-os-execute.md) |
| [`tug-109/`](tug-109/) | Can one report be compared with the previous build's, marking each problem resolved, new or still there? | [README.md](tug-109/README.md) |
| [`tug-123/`](tug-123/) | Does giving SAM several ways to describe a thing, on nearby frames, help it find more? | wiki: [SAM 3.1, several phrasings](../docs/wiki/sam-3-1.md#several-phrasings-and-nearby-frames-tug-123) |
| [`e2e-2026-10-27/`](e2e-2026-10-27/) | Does the whole pipeline (analyse, score, fix, compare, metrics) work end to end on the test sessions? It found and fixed one bug. | [README.md](e2e-2026-10-27/README.md) |
