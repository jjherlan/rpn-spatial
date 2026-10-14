# Workshop feedback: online form + name-blind live summary

| File | What it is |
|---|---|
| `feedback_form.gs` | Google Apps Script. Run once in a private Google Sheet: creates the Google Form, a Moderation tab and the anonymised **Public** tab |
| `feedback.qmd` → `../feedback.html` | Page that embeds the Google Form (shown in the app's *Feedback* tab) |
| `feedback-summary.qmd` → `../feedback-summary.html` | Live summary: reads the published Public tab every time it is opened |
| `../feedback-config.json` | The two links the pages need. Edit this file, commit, push: no re-render or re-export needed |
| `../feedback-demo.csv` | Made-up example data, shown (clearly labelled) until `public_csv_url` is set |
| `../feedback-form.pdf` | Paper version of the same form |

## One-time setup (about 10 minutes)

1. In Google Drive, create a new Google Sheet, e.g. *SCCS-NY 2026 feedback (PRIVATE)*. Keep it private.
2. **Extensions → Apps Script**. Delete the sample code, paste all of `feedback_form.gs`, click **Save**.
3. In the toolbar choose the function **`setup`**, click **Run**, and approve the permissions
   (Google warns that the app is unverified because it is your own script: *Advanced → Go to … (unsafe)*).
4. Back in the Sheet, open the new **Setup** tab. It lists the form link and the `form_embed_url`.
5. **File → Share → Publish to web** → *Link* → choose the **Public** tab (not "Entire document") and
   **Comma-separated values (.csv)** → **Publish**. Copy the link.
6. Edit `feedback-config.json` in the repository root:

   ```json
   {
     "form_embed_url": "https://docs.google.com/forms/d/e/…/viewform?embedded=true",
     "public_csv_url": "https://docs.google.com/spreadsheets/d/e/…/pub?gid=…&single=true&output=csv"
   }
   ```

7. Commit and push. Within a couple of minutes the app's *Feedback* tab shows the form and the summary page goes live.

## During and after the workshop

- **Moderation:** in the *Moderation* tab, tick **Approve comments** on a row to publish that response's written answers.
  Type in **Reply from presenter** to publish an answer under that participant's approved questions.
  The Public tab rebuilds automatically; use the **Feedback** menu → *Rebuild public summary* if needed.
- **What is public:** counts per question, plus approved comments sorted alphabetically within each question.
  Never public: names, emails, "main field", timestamps, response order or any individual's set of answers.
- **Freshness:** Google refreshes a published tab about every 5 minutes, so new responses take a few minutes to appear.
- **Paper forms:** type paper responses into the Google Form yourself, so they are counted the same way.
- **Closing the form:** in the Google Form, *Responses → Accepting responses* off. The summary stays online.
- **Never publish** the Setup, Moderation or *Form Responses* tabs, and do not share the Sheet.

## Rebuilding the pages (only if you edit the .qmd files)

```bash
cd feedback-src
quarto render feedback.qmd
quarto render feedback-summary.qmd
cp feedback.html feedback-summary.html ..
```

If you change questions in `feedback_form.gs` after setup, keep each `code` unchanged; the summary page needs no edit, because the Public tab carries its own labels.
