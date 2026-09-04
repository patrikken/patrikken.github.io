# ---------------------------------------------------------------------------
# Shared helpers for the publications list (publications.qmd) and the
# generated per-paper pages (generate_papers.R). Keeping them here means the
# two never drift apart.
# ---------------------------------------------------------------------------

# Read a column as a clean character vector. Returns "" for every row when the
# column does not exist yet, so new optional columns need no code change.
pu_col <- function(df, name) {
    if (!name %in% names(df)) {
        return(rep("", nrow(df)))
    }
    x <- df[[name]]
    if (is.list(x)) {
        x <- vapply(x, function(z) if (length(z) == 0) "" else as.character(z)[1],
            character(1)
        )
    } else {
        x <- as.character(x)
    }
    x[is.na(x)] <- ""
    trimws(x)
}

pu_esc <- function(x) {
    x <- gsub("&", "&amp;", x, fixed = TRUE)
    x <- gsub("<", "&lt;", x, fixed = TRUE)
    gsub(">", "&gt;", x, fixed = TRUE)
}

# "Journal, Workshop" -> c("Journal", "Workshop")
pu_split <- function(x) {
    lapply(x, function(cell) {
        parts <- trimws(unlist(strsplit(cell, ",")))
        parts[nzchar(parts)]
    })
}

pu_title_case <- function(x) {
    paste0(toupper(substr(x, 1, 1)), tolower(substr(x, 2, nchar(x))))
}

# "GradTune: Last-layer Fine-tuning…" -> "gradtune-last-layer-fine-tuning"
# Capped at 80 characters, but always on a word boundary — a slug ending in
# "...machine-learnin" is what a blind substr() gives you.
pu_slug <- function(x) {
    vapply(x, function(one) {
        s <- iconv(one, to = "ASCII//TRANSLIT", sub = "")
        s <- tolower(s)
        s <- gsub("[^a-z0-9]+", "-", s)
        s <- gsub("^-+|-+$", "", s)
        if (nchar(s) > 80) {
            words <- strsplit(s, "-", fixed = TRUE)[[1]]
            keep <- character(0)
            for (w in words) {
                if (nchar(paste(c(keep, w), collapse = "-")) > 80) break
                keep <- c(keep, w)
            }
            s <- if (length(keep)) paste(keep, collapse = "-") else substr(s, 1, 80)
        }
        s
    }, character(1), USE.NAMES = FALSE)
}

# ---------------------------------------------------------------------------
# Sheet access.
#
# generate_papers.R runs as a pre-render step on every `quarto render`. It
# fetches the whole spreadsheet once and drops it in PU_CACHE. Every page then
# reads from that snapshot, so:
#   * the spreadsheet is hit once per compile, not once per page;
#   * the news list, the publications list and the paper pages are guaranteed
#     to be built from the same rows.
# The fallback keeps a page working if it is ever rendered without the
# pre-render step having run.
# ---------------------------------------------------------------------------

PU_CACHE <- ".cv-cache/sheets.rds"

pu_sheet <- function(name, path = PU_CACHE) {
    if (file.exists(path)) {
        sheets <- readRDS(path)
        if (name %in% names(sheets)) {
            return(sheets[[name]])
        }
    }
    get_cv_data()(name)
}

pu_load_papers <- function() pu_sheet("Papers")

# One outlined chip; "" when the url is empty. Vectorised.
pu_chip <- function(url, icon, label) {
    ifelse(nzchar(url),
        paste0(
            '<a class="pub-link" href="', pu_esc(url), '" target="_blank" ',
            'rel="noopener"><i class="bi ', icon, '"></i>', label, "</a>"
        ),
        ""
    )
}

# Split an abstract on blank lines into <p> blocks.
pu_paragraphs <- function(x) {
    vapply(x, function(txt) {
        if (!nzchar(txt)) {
            return("")
        }
        parts <- trimws(unlist(strsplit(txt, "\n[ \t]*\n")))
        parts <- parts[nzchar(parts)]
        paste0("<p>", pu_esc(parts), "</p>", collapse = "")
    }, character(1), USE.NAMES = FALSE)
}

# The profile card shown beside the publications list and the paper pages.
pu_profile_html <- function() {
    paste0(
        '<div class="profile-card">',
        '<img class="profile-photo" src="/img/me.jpg" alt="Patrik Kenfack" ',
        'width="600" height="600">',
        '<p class="profile-name">Patrik Kenfack</p>',
        '<p class="profile-role">PhD Candidate,<br>Computer Science</p>',
        '<ul class="profile-list">',
        '<li><i class="bi bi-geo-alt-fill"></i><span>Montr', "é", "al QC, Canada</span></li>",
        '<li><i class="bi bi-building"></i><span><a href="https://www.etsmtl.ca/">',
        "É", 'TS Montr', "é", 'al</a> &amp; <a href="https://mila.quebec/">Mila</a></span></li>',
        '<li><i class="bi bi-mortarboard-fill"></i><span><a href="https://scholar.google.com/citations?user=bWvJMcgAAAAJ&amp;hl=fr&amp;oi=ao" target="_blank" rel="noopener">Google Scholar</a></span></li>',
        '<li><i class="bi bi-linkedin"></i><span><a href="https://www.linkedin.com/in/patrik-kenfack-30a8b933/" target="_blank" rel="noopener">LinkedIn</a></span></li>',
        '<li><i class="bi bi-github"></i><span><a href="https://github.com/patrikken" target="_blank" rel="noopener">GitHub</a></span></li>',
        '<li><i class="bi bi-envelope-fill"></i><span><a href="mailto:kenfackjoslin@gmail.com">Email</a></span></li>',
        "</ul></div>"
    )
}

# ---------------------------------------------------------------------------
# Derive everything both pages need from the Papers sheet, once.
# ---------------------------------------------------------------------------
pu_prepare <- function(papers) {
    p <- list()
    p$title <- pu_col(papers, "title")
    p$authors <- pu_col(papers, "authors")
    p$venue <- pu_col(papers, "venue")
    p$year <- pu_col(papers, "year")
    p$pub_date <- pu_col(papers, "pub_date")
    p$category <- pu_col(papers, "category")
    p$awards <- pu_col(papers, "awards")
    p$bibtex <- pu_col(papers, "bibtex")
    p$abstract <- pu_col(papers, "abstract")
    p$published_url <- pu_col(papers, "published_url")
    p$pdf <- pu_col(papers, "pdf")

    # a blank `year` cell would otherwise create an untitled group on the
    # listing; fall back to the year inside pub_date
    from_date <- ifelse(grepl("\\d{4}", p$pub_date),
        sub(".*?(\\d{4}).*", "\\1", p$pub_date), "")
    p$year <- ifelse(nzchar(p$year), p$year, from_date)

    p$slug <- pu_slug(p$title)
    p$page_url <- paste0("/papers/", p$slug, "/")

    # bold my own name however the sheet spells it
    p$authors_html <- gsub("(Patrik(?:\\s+Joslin)?\\s+Kenfack)", "<strong>\\1</strong>",
        pu_esc(p$authors),
        perl = TRUE
    )

    # one pill per category value; a workshop paper later published in a
    # journal is a single row reading "Journal, Workshop"
    p$cat_html <- vapply(pu_split(p$category), function(cs) {
        if (!length(cs)) {
            return("")
        }
        slugs <- tolower(gsub("[^A-Za-z]", "", cs))
        slugs[!nzchar(slugs)] <- "other"
        paste0('<span class="pub-tag" data-category="', slugs, '">',
            pu_esc(pu_title_case(cs)), "</span>",
            collapse = ""
        )
    }, character(1))

    # the awards cell verbatim; the trophy is only added when the cell does
    # not already start with its own emoji or symbol
    p$award_html <- ifelse(nzchar(p$awards),
        paste0(
            '<span class="pub-award">',
            ifelse(grepl("^[A-Za-z0-9]", p$awards), '<i class="bi bi-award"></i>', ""),
            pu_esc(p$awards), "</span>"
        ),
        ""
    )

    # the blog column may hold several links: "Blog 1", "Blog 2", …
    blog_html <- vapply(pu_split(pu_col(papers, "blog")), function(us) {
        if (!length(us)) {
            return("")
        }
        labs <- if (length(us) == 1) "Blog" else paste("Blog", seq_along(us))
        paste0(pu_chip(us, "bi-journal-text", labs), collapse = "")
    }, character(1))

    p$links <- paste0(
        pu_chip(p$published_url, "bi-link-45deg", "Paper"),
        pu_chip(p$pdf, "bi-file-earmark-pdf", "PDF"),
        pu_chip(pu_col(papers, "code"), "bi-github", "Code"),
        pu_chip(pu_col(papers, "slides"), "bi-easel", "Slides"),
        pu_chip(pu_col(papers, "poster"), "bi-image", "Poster"),
        pu_chip(pu_col(papers, "video"), "bi-play-btn", "Video"),
        blog_html
    )

    ids <- paste0("bib-", seq_len(nrow(papers)))
    p$cite_btn <- ifelse(nzchar(p$bibtex),
        paste0(
            '<button type="button" class="pub-link pub-cite" data-target="', ids,
            '" aria-expanded="false"><i class="bi bi-quote"></i>Cite</button>'
        ), ""
    )
    p$cite_box <- ifelse(nzchar(p$bibtex),
        paste0(
            '<div class="pub-bibtex" id="', ids, '" hidden>',
            '<button type="button" class="pub-copy">Copy</button>',
            "<pre><code>", pu_esc(trimws(p$bibtex)), "</code></pre></div>"
        ), ""
    )

    # "Published in <em>Venue</em>, 2025"
    p$venue_line <- ifelse(nzchar(p$venue),
        paste0(
            "Published in <em>", pu_esc(p$venue), "</em>",
            ifelse(nzchar(p$year), paste0(", ", pu_esc(p$year)), "")
        ),
        ifelse(nzchar(p$year), pu_esc(p$year), "")
    )

    p$n <- nrow(papers)
    p
}

# The JS behind the Cite chips; identical on both pages.
pu_cite_script <- function() {
    paste0(
        "<script>\n",
        'document.addEventListener("click", function (e) {\n',
        '  const toggle = e.target.closest(".pub-cite");\n',
        "  if (toggle) {\n",
        "    const box = document.getElementById(toggle.dataset.target);\n",
        "    if (box) {\n",
        "      box.hidden = !box.hidden;\n",
        '      toggle.setAttribute("aria-expanded", String(!box.hidden));\n',
        '      toggle.classList.toggle("is-open", !box.hidden);\n',
        "    }\n    return;\n  }\n",
        '  const copy = e.target.closest(".pub-copy");\n',
        "  if (copy) {\n",
        '    const text = copy.parentElement.querySelector("code").innerText;\n',
        "    navigator.clipboard.writeText(text).then(function () {\n",
        "      const original = copy.textContent;\n",
        '      copy.textContent = "Copied";\n',
        '      copy.classList.add("is-copied");\n',
        "      setTimeout(function () {\n",
        "        copy.textContent = original;\n",
        '        copy.classList.remove("is-copied");\n',
        "      }, 1600);\n    });\n  }\n});\n</script>"
    )
}
