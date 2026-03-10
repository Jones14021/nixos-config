# 📝 LaTeX IDE - Quick Reference

Welcome to your robust, Nix-managed local LaTeX environment! 
This environment is powered by **Tectonic** (which downloads missing packages automatically) and **VS Code**.

## ⌨️ Essential Keyboard Shortcuts

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| `Ctrl + S` | **Save, Format & Build** | Saves the file, runs `tex-fmt` to format your code, and triggers Tectonic to compile the PDF. |
| `Ctrl + Alt + J` | **SyncTeX (Forward)** | Jumps the PDF Viewer to the exact position of your text cursor in the code. |
| `Ctrl + Click` | **SyncTeX (Backward)** | Click anywhere in the PDF Viewer to jump your text cursor to that exact line in the code. |

## 📚 Zotero & natbib citation Workflow (outdated)

This environment is pre-configured to work seamlessly with Zotero.

1. **In Zotero:** Install the *Better BibTeX* plugin.
2. **Export:** Right-click your collection -> Export -> Format: **Better BibTeX** -> Check "Keep updated".
3. **Save:** Save it in your LaTeX folder as `references.bib`.
4. **Link it:** At the end of your `.tex` file, use:
   ```latex
   \bibliography{references}
   \bibliographystyle{icml2012}
   ```
5. **Cite:** Type `\cite{` in VS Code to automatically search and insert papers from your auto-updating Zotero file.
   - Use `\cite{key}` for standard citations: (Author, Year)
   - Use `\yrcite{key}` for year only: (Year)
   - Hover over any `\cite{...}` in your code to preview the abstract!

Here is the additional paragraph for the `biblatex` / `biber` workflow. You can just insert this right below the `natbib` section in your `cheatsheet.md`.

## 📘 Modern Citation Workflow (biblatex / biber)

If you are starting a fresh project and are not forced to use an older template (like ICML 2012), the modern standard is `biblatex` with the `biber` backend. This environment fully supports it!

1. **In Zotero:** Export your collection using the format **Better BibLaTeX** (check "Keep updated") and save as `references.bib`.
2. **In your Preamble:** Instead of using `natbib`, set up `biblatex`:
   ```latex
   \usepackage[backend=biber, style=apa]{biblatex}
   \addbibresource{references.bib}
   ```
3. **Print Bibliography:** Place this command where the references should appear:
   ```latex
   \printbibliography
   ```
4. **Cite:** Type `\parencite{` for (Author, Year) or `\textcite{` for Author (Year). Tectonic will automatically detect `biber`, run it, and link your citations on save.


## ⚙️ How it works under the hood
- **No internet needed for builds:** Unless you use a `\usepackage{}` you've never used before. Tectonic fetches it once and caches it locally.
- **Isolated Environment:** This editor runs completely independent of your regular VS Code to prevent extension conflicts.
