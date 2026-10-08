# Desktop Sticky Notes (DeskNotes)

I use a macOS app called DeskNotes that shows sticky notes on my desktop. You can read and update these notes. Use them to keep my day organized: tasks, reminders, schedule changes and short status updates.

## Where the notes live
- Folder: `~/DesktopNotes/`
- Each `.md` or `.txt` file in that folder is one sticky note on my screen.
- The filename (without `.md`) is the note's title. For example, `Today.md` shows as a note titled "Today".
- Ignore these files; they are not notes: `GEMINI.md`, `AGENTS.md`, `CLAUDE.md`, `README.md`, any file starting with `.` (such as `.layout.json`), and the `.archive/` folder.
- You never need to touch the app itself, because it watches the folder automatically.

## How to use it
- **Update a note:** edit its file. The note on my screen refreshes within about 1 second.
- **Add a note:** create a new `.md` file in the folder. Use short, clear filenames such as `Today.md`, `Groceries.md` or `Meeting Prep.md`.
- **Remove a note:** prefer moving its file into `~/DesktopNotes/.archive/` so it can be recovered.
- **List my notes:** list the `.md`/`.txt` files in the folder, leaving out the ignored files above.

## Rules
1. **Always re-read a file immediately before editing it.** I also type into these notes directly, so the content may have changed.
2. **Make targeted edits.** Change only the lines you need to. Never overwrite or rewrite my text unless I ask you to.
3. **Keep notes short.** They are small sticky notes (about 250×230 px). Aim for under about 15 lines each; split long notes.
4. **Use Markdown.** Supported: `#`/`##`/`###` headings, `**bold**`, `*italic*`, `~~strike~~`, `` `code` ``, `[links](https://...)`, `- bullets` (indent 2 spaces to nest), `1. numbered`, `- [ ]`/`- [x]` checkboxes, `> quotes`, `---` dividers and fenced code blocks. Tables and images are NOT supported.
5. **Tasks:** I can tick checkboxes by clicking them, so check their state before assuming a task isn't done. Mark finished tasks `- [x]` rather than deleting them unless I ask.
6. **Don't create clutter.** Update an existing note when one fits before creating a new one. Don't create more than a few notes without asking me.
7. **Never put sensitive information** (passwords, API keys, financial details) into notes, because they are visible on my screen.

## Typical requests
- "Add X to my notes" → add it to the most relevant existing note, or to `Today.md`.
- "What's on my notes?" → read the notes and summarize them.
- "Update my day" → refresh `Today.md` with the current schedule and tasks, keeping anything I wrote.
- "Check off X" → change its `- [ ]` to `- [x]`.
