import fs from 'node:fs/promises'
import path from 'node:path'
import matter from 'gray-matter'
import MarkdownIt from 'markdown-it'
import anchor from 'markdown-it-anchor'
import { createHighlighter } from 'shiki'
import { renderMermaidSVG } from 'beautiful-mermaid'

const root = process.cwd()
const outDir = path.join(root, 'site-dist')
const assetsDir = path.join(root, 'site/assets')
const pragmataSourceDir = process.env.PRAGMATA_PRO_DIR ?? path.join(process.env.HOME ?? '', 'Downloads/PragmataPro0.903')
const bundlePragmata = process.env.BUNDLE_PRAGMATA_PRO === '1'

const collections = [
  { key: 'masterplans', label: 'Master Plans', dir: 'docs/masterplans', route: 'masterplans', kind: 'master-plan' },
  { key: 'plans', label: 'Exec Plans', dir: 'docs/plans', route: 'plans', kind: 'exec-plan' },
  { key: 'foundations', label: 'Foundations', dir: 'docs/foundations', route: 'foundations', kind: 'foundation' },
  { key: 'guide', label: 'Guides', dir: 'docs/guide', route: 'guide', kind: 'guide', excludeDirs: ['diagrams'] },
  { key: 'diagrams', label: 'Diagrams', dir: 'docs/guide/diagrams', route: 'diagrams', kind: 'diagram', extensions: ['.md', '.mmd'] },
  { key: 'research', label: 'Research', dir: 'docs/research', route: 'research', kind: 'research' },
]

const shikiTheme = 'github-light'
const languages = ['haskell', 'sql', 'bash', 'json', 'yaml', 'markdown', 'typescript', 'javascript', 'text']
const highlighter = await createHighlighter({ themes: [shikiTheme], langs: languages })
const loadedLangs = new Set(languages)

const diagramTheme = {
  bg: '#fbfaf7',
  fg: '#202124',
  line: '#59616d',
  accent: '#246f74',
  muted: '#777063',
  surface: '#f2efe7',
  border: '#c8c0b2',
  font: 'Inter',
  transparent: true,
  padding: 28,
  nodeSpacing: 28,
  layerSpacing: 46,
  thoroughness: 5,
}

const md = new MarkdownIt({
  html: false,
  linkify: true,
  typographer: true,
  highlight(code, lang) {
    const cleanLang = normalizeLang(lang)
    if (cleanLang === 'mermaid') return `<figure class="diagram diagram-from-doc">${renderDiagram(code)}</figure>`
    return highlightCode(code, cleanLang)
  },
}).use(anchor, {
  slugify,
  permalink: anchor.permalink.linkInsideHeader({
    symbol: '#',
    placement: 'after',
    class: 'anchor-link',
    ariaHidden: true,
  }),
})

md.renderer.rules.code_block = (tokens, idx) => highlightCode(tokens[idx].content, inferCodeLang(tokens[idx].content))
md.renderer.rules.fence = (tokens, idx) => {
  const token = tokens[idx]
  const lang = normalizeLang(token.info)
  if (lang === 'mermaid') return `<figure class="diagram diagram-from-doc">${renderDiagram(token.content)}</figure>`
  return highlightCode(token.content, lang)
}

await fs.rm(outDir, { recursive: true, force: true })
await fs.mkdir(outDir, { recursive: true })
await fs.cp(assetsDir, path.join(outDir, 'assets'), { recursive: true })
const hasPragmataAssets = await copyPragmataAssets()
await fs.cp(path.join(root, 'docs'), path.join(outDir, 'docs'), {
  recursive: true,
  filter: (source) => !source.endsWith('.DS_Store'),
})

const allDocs = []
const byCollection = new Map()

for (const collection of collections) {
  const docs = await loadCollection(collection)
  byCollection.set(collection.key, docs)
  allDocs.push(...docs)
}

const routeBySource = new Map(allDocs.map((doc) => [doc.sourcePath, `${doc.route}/${doc.slug}.html`]))
const masterBySource = new Map(byCollection.get('masterplans').map((doc) => [doc.sourcePath, doc]))
const plansByMaster = new Map()
for (const plan of byCollection.get('plans')) {
  if (!plan.masterPlan) continue
  const list = plansByMaster.get(plan.masterPlan) ?? []
  list.push(plan)
  plansByMaster.set(plan.masterPlan, list)
}

for (const [source, plans] of plansByMaster) {
  plans.sort((a, b) => a.id - b.id)
  const master = masterBySource.get(source)
  if (master) master.children = plans
}

for (const doc of allDocs) {
  doc.html = renderDocHtml(doc)
}

for (const collection of collections) {
  await fs.mkdir(path.join(outDir, collection.route), { recursive: true })
  const docs = byCollection.get(collection.key)
  for (const doc of docs) {
    const html = docPage(doc)
    await fs.writeFile(path.join(outDir, collection.route, `${doc.slug}.html`), html, 'utf8')
    const fileSlug = doc.file.replace(doc.extension, '')
    if (fileSlug !== doc.slug) {
      await fs.writeFile(path.join(outDir, collection.route, `${fileSlug}.html`), html, 'utf8')
    }
  }
  await fs.writeFile(path.join(outDir, collection.route, 'index.html'), collectionPage(collection, docs), 'utf8')
}

await fs.writeFile(path.join(outDir, 'index.html'), indexPage(), 'utf8')
await fs.writeFile(path.join(outDir, 'styles.css'), stylesheet(hasPragmataAssets), 'utf8')
await fs.writeFile(path.join(outDir, 'app.js'), clientScript(), 'utf8')

console.log(`Built ${allDocs.length + collections.length + 1} site pages into site-dist/`)

async function loadCollection(collection) {
  const dir = path.join(root, collection.dir)
  const extensions = collection.extensions ?? ['.md']
  const files = (await fs.readdir(dir, { withFileTypes: true }))
    .filter((entry) => entry.isFile() && extensions.includes(path.extname(entry.name)))
    .map((entry) => entry.name)
    .sort(naturalFileSort)

  const docs = []
  for (const file of files) {
    const abs = path.join(dir, file)
    const raw = await fs.readFile(abs, 'utf8')
    const sourcePath = `${collection.dir}/${file}`
    const ext = path.extname(file)
    const parsed = ext === '.md' ? matter(raw) : { data: {}, content: raw }
    const id = Number(parsed.data.id ?? (/^(\d+)/.exec(file)?.[1] ?? docs.length))
    const slug = parsed.data.slug ?? file.replace(ext, '')
    const title = parsed.data.title ?? extractTitle(parsed.content) ?? titleFromSlug(slug.replace(/^\d+-/, ''))
    const isMermaidSource = ext === '.mmd'
    const content = isMermaidSource ? mermaidDocMarkdown(title, parsed.content) : parsed.content
    docs.push({
      id,
      slug,
      title,
      file,
      extension: ext,
      sourcePath,
      route: collection.route,
      collectionKey: collection.key,
      collectionLabel: collection.label,
      kind: parsed.data.kind ?? collection.kind,
      createdAt: parsed.data.created_at,
      masterPlan: parsed.data.master_plan,
      summary: isMermaidSource ? `Rendered Mermaid topology source from ${sourcePath}.` : extractLead(content),
      headings: extractHeadings(content),
      stats: docStats(content),
      content,
      children: [],
      isMermaidSource,
    })
  }
  return docs
}

function renderDocHtml(doc) {
  let html = md.render(doc.content)
  html = rewriteDocLinks(html, doc)
  return html
}

function indexPage() {
  const masterplans = byCollection.get('masterplans')
  const plans = byCollection.get('plans')
  const standalone = plans.filter((plan) => !plan.masterPlan || !masterBySource.has(plan.masterPlan))
  const guideDocs = byCollection.get('guide')
  const research = byCollection.get('research')
  const foundations = byCollection.get('foundations')
  const diagrams = byCollection.get('diagrams')
  const totalWords = allDocs.reduce((n, doc) => n + doc.stats.words, 0)
  const graph = renderDiagram(masterPlanGraph(masterplans, standalone))

  return shell({
    title: 'Keiki Documentation',
    active: 'overview',
    body: `
      <section class="hero">
        <p class="eyebrow">keiki</p>
        <h1>Symbolic-register transducer documentation map</h1>
        <p class="hero-copy">A deployable reading site generated from keiki's documentation corpus. Master plans, child exec plans, foundations, guides, diagrams, and research notes are all connected without modifying the source Markdown.</p>
        <div class="hero-actions">
          <a class="button primary" href="masterplans/">Master plans</a>
          <a class="button" href="foundations/">Start with foundations</a>
          <a class="button" href="guide/">Guides</a>
        </div>
      </section>

      <section class="metric-grid" aria-label="Documentation metrics">
        ${metric('Master plans', masterplans.length)}
        ${metric('Exec plans', plans.length)}
        ${metric('Foundations', foundations.length)}
        ${metric('Guides', guideDocs.length)}
        ${metric('Research notes', research.length)}
        ${metric('Diagrams', diagrams.length)}
      </section>

      <section class="split">
        <article>
          <p class="eyebrow">Plan topology</p>
          <h2>Master plans own the implementation story</h2>
          <p>Each master plan page lists the child exec plans resolved from <code>master_plan</code> frontmatter. Standalone exec plans are kept visible so operational upgrades, benchmark work, and newer exploratory plans do not disappear.</p>
        </article>
        <figure class="diagram">${graph}</figure>
      </section>

      <section class="collection-band">
        <div class="section-heading">
          <p class="eyebrow">Collections</p>
          <h2>Browse by reading mode</h2>
        </div>
        <div class="collection-grid">
          ${collections.map((collection) => collectionCard(collection, byCollection.get(collection.key))).join('')}
        </div>
      </section>

      <section class="collection-band">
        <div class="section-heading">
          <p class="eyebrow">Current shape</p>
          <h2>Master plan index</h2>
        </div>
        <div class="doc-grid">
          ${masterplans.map((doc) => docCard(doc, 'masterplans/', { childCount: doc.children.length })).join('')}
        </div>
      </section>
    `,
  })
}

function collectionPage(collection, docs) {
  const words = docs.reduce((n, doc) => n + doc.stats.words, 0)
  const sections = docs.reduce((n, doc) => n + doc.stats.sections, 0)
  const bodyExtra = collection.key === 'plans' ? standalonePlansSection() : ''
  return shell({
    title: `${collection.label} / Keiki`,
    active: collection.key,
    basePath: '../',
    body: `
      <section class="hero">
        <p class="eyebrow">${escapeHtml(collection.label)}</p>
        <h1>${escapeHtml(collection.label)}</h1>
        <p class="hero-copy">${escapeHtml(collectionIntro(collection.key))}</p>
      </section>

      <section class="metric-grid compact" aria-label="${escapeHtml(collection.label)} metrics">
        ${metric('Documents', docs.length)}
        ${metric('Sections', sections)}
        ${metric('Words', words.toLocaleString())}
        ${metric('Code blocks', docs.reduce((n, doc) => n + doc.stats.codeBlocks, 0))}
        ${metric('Decisions', docs.reduce((n, doc) => n + doc.stats.decisions, 0))}
        ${metric('Done items', docs.reduce((n, doc) => n + doc.stats.checked, 0))}
      </section>

      ${collection.key === 'masterplans' ? masterPlanMapSection(docs) : ''}
      ${bodyExtra}

      <section class="collection-band">
        <div class="toolbar">
          <label class="search-label" for="doc-search">Filter</label>
          <input id="doc-search" type="search" placeholder="Search titles, summaries, paths..." autocomplete="off">
        </div>
        <div class="doc-grid" data-doc-list>
          ${docs.map((doc) => docCard(doc, '', { childCount: doc.children.length })).join('')}
        </div>
      </section>
    `,
  })
}

function docPage(doc) {
  const basePath = '../'
  const collectionDocs = byCollection.get(doc.collectionKey)
  const index = collectionDocs.findIndex((candidate) => candidate.sourcePath === doc.sourcePath)
  const previous = collectionDocs[index - 1]
  const next = collectionDocs[index + 1]
  const master = doc.masterPlan ? masterBySource.get(doc.masterPlan) : null
  const childSection = doc.collectionKey === 'masterplans' ? childPlanSection(doc) : ''
  const related = relatedSection(doc, master)

  return shell({
    title: `${doc.title} / Keiki`,
    active: doc.collectionKey,
    basePath,
    body: `
      <article class="doc-shell">
        <header class="doc-header">
          <p class="eyebrow">${escapeHtml(doc.collectionLabel)} ${doc.id ? String(doc.id).padStart(2, '0') : ''}</p>
          <h1>${escapeHtml(doc.title)}</h1>
          <p>${escapeHtml(doc.summary)}</p>
          <div class="doc-actions">
            <a class="button primary" href="#source">Read enhanced doc</a>
            <a class="button" href="../${escapeHtml(doc.sourcePath)}">Original source</a>
            <a class="button" href="index.html">${escapeHtml(doc.collectionLabel)} index</a>
            ${master ? `<a class="button" href="../masterplans/${master.slug}.html">Parent master plan</a>` : ''}
          </div>
        </header>

        <section class="metric-grid compact">
          ${metric('Sections', doc.stats.sections)}
          ${metric('Words', doc.stats.words.toLocaleString())}
          ${metric('Code blocks', doc.stats.codeBlocks)}
          ${metric('Done items', doc.stats.checked)}
          ${metric('Open items', doc.stats.unchecked)}
          ${metric('Decisions', doc.stats.decisions)}
        </section>

        ${childSection}
        ${related}

        <div class="doc-layout">
          <aside class="toc">
            <p class="toc-title">On this page</p>
            <nav>${toc(doc.headings)}</nav>
          </aside>
          <main id="source" class="markdown-body">
            ${doc.html}
          </main>
        </div>

        <footer class="pager">
          ${previous ? `<a class="button" href="${previous.slug}.html">Previous: ${escapeHtml(previous.title)}</a>` : '<span></span>'}
          ${next ? `<a class="button primary" href="${next.slug}.html">Next: ${escapeHtml(next.title)}</a>` : `<a class="button primary" href="index.html">Back to ${escapeHtml(doc.collectionLabel)}</a>`}
        </footer>
      </article>
    `,
  })
}

function shell({ title, body, active, basePath = '' }) {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>${escapeHtml(title)}</title>
    <link rel="stylesheet" href="${basePath}styles.css">
  </head>
  <body>
    <a class="skip-link" href="#content">Skip to content</a>
    <header class="topbar">
      <a class="brand" href="${basePath}index.html" aria-label="Keiki overview">
        <span class="brand-mark">系</span>
        <span>keiki docs</span>
      </a>
      <nav class="topnav" aria-label="Primary">
        <a class="${active === 'overview' ? 'active' : ''}" href="${basePath}index.html">Overview</a>
        ${collections.map((collection) => `<a class="${active === collection.key ? 'active' : ''}" href="${basePath}${collection.route}/">${escapeHtml(navLabel(collection.key))}</a>`).join('')}
      </nav>
    </header>
    <main id="content">
      ${body}
    </main>
    <script type="module" src="${basePath}app.js"></script>
  </body>
</html>`
}

function childPlanSection(master) {
  if (!master.children.length) return ''
  return `<section class="collection-band inset">
    <div class="section-heading">
      <p class="eyebrow">Child exec plans</p>
      <h2>${master.children.length} linked plans</h2>
    </div>
    <div class="doc-grid compact-cards">
      ${master.children.map((plan) => docCard(plan, '../plans/')).join('')}
    </div>
  </section>`
}

function relatedSection(doc, master) {
  if (doc.collectionKey !== 'plans' || !master) return ''
  const siblings = master.children.filter((plan) => plan.sourcePath !== doc.sourcePath).slice(0, 5)
  return `<section class="collection-band inset">
    <div class="section-heading">
      <p class="eyebrow">Parent initiative</p>
      <h2><a href="../masterplans/${master.slug}.html">${escapeHtml(master.title)}</a></h2>
      <p class="section-copy">${escapeHtml(master.summary)}</p>
    </div>
    ${siblings.length ? `<div class="doc-grid compact-cards">${siblings.map((plan) => docCard(plan, '')).join('')}</div>` : ''}
  </section>`
}

function standalonePlansSection() {
  const plans = byCollection.get('plans')
  const standalone = plans.filter((plan) => !plan.masterPlan || !masterBySource.has(plan.masterPlan))
  if (!standalone.length) return ''
  return `<section class="collection-band inset">
    <div class="section-heading">
      <p class="eyebrow">Standalone</p>
      <h2>Plans without a parent master plan</h2>
      <p class="section-copy">These are still first-class work items: infrastructure upgrades, later feature work, and recent exploratory plans.</p>
    </div>
    <div class="doc-grid compact-cards">
      ${standalone.map((plan) => docCard(plan, '')).join('')}
    </div>
  </section>`
}

function masterPlanMapSection(masterplans) {
  return `<section class="split">
    <article>
      <p class="eyebrow">Dependency map</p>
      <h2>Master plan to exec plan fan-out</h2>
      <p>Cards below show child plan counts. Open a master plan to read its scope, registry, decision log, and linked child plans in one place.</p>
    </article>
    <figure class="diagram">${renderDiagram(masterPlanGraph(masterplans, []))}</figure>
  </section>`
}

function collectionCard(collection, docs) {
  return `<a class="collection-card" href="${collection.route}/">
    <span>${escapeHtml(navLabel(collection.key))}</span>
    <strong>${docs.length}</strong>
    <p>${escapeHtml(collectionIntro(collection.key))}</p>
  </a>`
}

function docCard(doc, prefix = '', options = {}) {
  const childText = options.childCount ? `${options.childCount} child plans` : doc.kind
  return `<article class="doc-card" data-doc-card data-search="${escapeHtml(`${doc.title} ${doc.summary} ${doc.sourcePath}`.toLowerCase())}">
    <div class="card-kicker">${escapeHtml(labelForDoc(doc))}</div>
    <h3><a href="${prefix}${doc.slug}.html">${escapeHtml(doc.title)}</a></h3>
    <p>${escapeHtml(doc.summary)}</p>
    <dl class="card-stats">
      <div><dt>sections</dt><dd>${doc.stats.sections}</dd></div>
      <div><dt>words</dt><dd>${doc.stats.words.toLocaleString()}</dd></div>
      <div><dt>scope</dt><dd>${escapeHtml(childText)}</dd></div>
    </dl>
  </article>`
}

function metric(label, value) {
  return `<div class="metric"><span>${escapeHtml(String(value))}</span><p>${escapeHtml(label)}</p></div>`
}

function toc(headings) {
  const items = headings.filter((heading) => heading.level <= 3)
  if (!items.length) return '<span class="toc-empty">No headings</span>'
  return items.map((heading) => `<a class="toc-level-${heading.level}" href="#${heading.id}">${escapeHtml(heading.text)}</a>`).join('')
}

function masterPlanGraph(masterplans, standalone) {
  const lines = ['flowchart LR']
  for (const mp of masterplans) {
    const id = `MP${mp.id}`
    lines.push(`  ${id}[MP-${mp.id}: ${escapeMermaid(mp.title)}]`)
    const children = mp.children.slice(0, 5)
    for (const child of children) {
      lines.push(`  ${id} --> EP${child.id}[EP-${child.id}]`)
    }
    if (mp.children.length > children.length) lines.push(`  ${id} --> More${mp.id}[+${mp.children.length - children.length} more]`)
  }
  if (standalone.length) {
    lines.push('  S[Standalone exec plans]')
    for (const plan of standalone.slice(0, 5)) lines.push(`  S --> EP${plan.id}[EP-${plan.id}]`)
  }
  return lines.join('\n')
}

function rewriteDocLinks(html, currentDoc) {
  return html.replace(/href="([^"]+)"/g, (match, href) => {
    if (/^(https?:|mailto:|#)/.test(href)) return match
    const [target, hash = ''] = href.split('#')
    const normalized = normalizeDocPath(target, currentDoc)
    const generated = routeBySource.get(normalized)
    if (generated) return `href="../${generated}${hash ? `#${hash}` : ''}"`
    if (normalized?.startsWith('docs/')) return `href="../${normalized}${hash ? `#${hash}` : ''}"`
    return match
  })
}

function normalizeDocPath(target, currentDoc) {
  if (!target) return ''
  if (target.startsWith('/')) return target.slice(1)
  if (target.startsWith('docs/')) return target
  const currentDir = path.posix.dirname(currentDoc.sourcePath)
  return path.posix.normalize(path.posix.join(currentDir, target))
}

function mermaidDocMarkdown(title, source) {
  return `# ${title}\n\n\`\`\`mermaid\n${source.trim()}\n\`\`\`\n`
}

function renderDiagram(source) {
  try {
    return renderMermaidSVG(source, diagramTheme)
      .replace(/\s*@import url\('https:\/\/fonts\.googleapis\.com\/css2\?family=Inter:[^']+'\);\n?/g, '')
  } catch (error) {
    return `<pre class="diagram-error"><code>${escapeHtml(source)}</code></pre>`
  }
}

function highlightCode(code, lang) {
  const language = loadedLangs.has(lang) ? lang : 'text'
  return highlighter.codeToHtml(code, { lang: language, theme: shikiTheme })
}

function normalizeLang(lang = '') {
  const clean = String(lang).trim().split(/\s+/)[0].toLowerCase()
  if (clean === 'hs') return 'haskell'
  if (clean === 'sh' || clean === 'shell') return 'bash'
  if (clean === 'yml') return 'yaml'
  if (!clean) return 'text'
  return clean
}

function inferCodeLang(code) {
  const trimmed = code.trim()
  if (/^(data|newtype|type|class|instance|module|import|[a-zA-Z0-9_']+\s*::|\{-#)/m.test(trimmed)) return 'haskell'
  if (/^(cabal|nix|ghci>|mkdir|cd|rg|grep|git|#\s)/m.test(trimmed)) return 'bash'
  if (/^(SELECT|CREATE|ALTER|INSERT|UPDATE|DELETE)\b/im.test(trimmed)) return 'sql'
  if (/^[\[{]/.test(trimmed)) return 'json'
  return 'text'
}

function docStats(markdown) {
  return {
    checked: count(markdown, /^\s*-\s+\[x\]/gim),
    unchecked: count(markdown, /^\s*-\s+\[ \]/gim),
    decisions: count(markdown, /^-\s+Decision:/gim),
    discoveries: count(markdown, /^-\s+\d{4}-\d{2}-\d{2}:/gim),
    sections: count(markdown, /^##\s+/gim),
    codeBlocks: count(markdown, /```|~~~|^( {4}|\t)\S/gm),
    words: markdown.split(/\s+/).filter(Boolean).length,
  }
}

function extractHeadings(markdown) {
  return markdown
    .split('\n')
    .map((line) => /^(#{1,3})\s+(.+)$/.exec(line))
    .filter(Boolean)
    .map((match) => ({
      level: match[1].length,
      text: stripMarkdown(match[2]),
      id: slugify(stripMarkdown(match[2])),
    }))
}

function extractTitle(markdown) {
  const match = /^#\s+(.+)$/m.exec(markdown)
  return match ? stripMarkdown(match[1]) : null
}

function extractLead(markdown) {
  const preferred = extractSectionLead(markdown, 'Vision & Scope') || extractSectionLead(markdown, 'Purpose / Big Picture') || extractSectionLead(markdown, 'Overview')
  if (preferred) return preferred
  const lines = markdown.split('\n')
  const collected = []
  for (const line of lines) {
    if (/^#{1,6}\s+/.test(line) || /^---\s*$/.test(line)) continue
    if (!line.trim()) {
      if (collected.length > 0) break
      continue
    }
    if (/^[-*]\s+|^\d+\.\s+/.test(line.trim())) {
      if (collected.length > 0) break
      continue
    }
    collected.push(line.trim())
  }
  return stripMarkdown(collected.join(' ')).slice(0, 420)
}

function extractSectionLead(markdown, heading) {
  const lines = markdown.split('\n')
  const start = lines.findIndex((line) => line.trim() === `## ${heading}`)
  if (start === -1) return ''
  const collected = []
  for (let i = start + 1; i < lines.length; i += 1) {
    const line = lines[i]
    if (/^#{1,6}\s+/.test(line)) break
    if (!line.trim()) {
      if (collected.length > 0) break
      continue
    }
    if (/^\d+\.\s|^-\s/.test(line.trim())) {
      if (collected.length > 0) break
      continue
    }
    collected.push(line.trim())
  }
  return stripMarkdown(collected.join(' ')).slice(0, 420)
}

function collectionIntro(key) {
  return {
    masterplans: 'Large initiatives with scope, decomposition strategy, registries, and cross-plan decision logs.',
    plans: 'Individual execution plans, linked back to parent master plans when frontmatter declares one.',
    foundations: 'Conceptual reading path for the formalism: event sourcing, finite automata, projections, and data-carrying alphabets.',
    guide: 'User-facing guides and tutorials for using keiki in real examples.',
    diagrams: 'Rendered topology diagrams and Mermaid source generated from Keiki.Render.Mermaid.',
    research: 'Design notes, prior-art analysis, and technical investigations backing the current library shape.',
  }[key]
}

function navLabel(key) {
  return {
    masterplans: 'Master',
    plans: 'Plans',
    foundations: 'Foundations',
    guide: 'Guides',
    diagrams: 'Diagrams',
    research: 'Research',
  }[key] ?? key
}

function labelForDoc(doc) {
  if (doc.collectionKey === 'masterplans') return `MP-${doc.id}`
  if (doc.collectionKey === 'plans') return `EP-${doc.id}`
  if (doc.collectionKey === 'diagrams') return doc.extension === '.mmd' ? 'Mermaid source' : 'Diagram note'
  return doc.collectionLabel
}

function naturalFileSort(a, b) {
  const na = Number(/^(\d+)/.exec(a)?.[1] ?? Number.MAX_SAFE_INTEGER)
  const nb = Number(/^(\d+)/.exec(b)?.[1] ?? Number.MAX_SAFE_INTEGER)
  return na === nb ? a.localeCompare(b) : na - nb
}

function titleFromSlug(slug) {
  return slug.split('-').map((word) => word ? word[0].toUpperCase() + word.slice(1) : word).join(' ')
}

function slugify(value) {
  return String(value)
    .toLowerCase()
    .replace(/`([^`]+)`/g, '$1')
    .replace(/[^\p{Letter}\p{Number}\s-]/gu, '')
    .trim()
    .replace(/\s+/g, '-')
}

function stripMarkdown(value) {
  return String(value)
    .replace(/`([^`]+)`/g, '$1')
    .replace(/\*\*([^*]+)\*\*/g, '$1')
    .replace(/\*([^*]+)\*/g, '$1')
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .replace(/#+\s*/g, '')
    .trim()
}

function count(value, regex) {
  return [...value.matchAll(regex)].length
}

function escapeMermaid(value) {
  return String(value).replaceAll('[', '(').replaceAll(']', ')').replaceAll('"', "'").slice(0, 54)
}

function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;')
}

async function copyPragmataAssets() {
  if (!bundlePragmata) return false

  const files = [
    ['PragmataPro_Mono_R_liga_0903.ttf', 'PragmataPro-Mono-Regular-Liga.ttf'],
    ['PragmataPro_Mono_B_liga_0903.ttf', 'PragmataPro-Mono-Bold-Liga.ttf'],
  ]
  const targetDir = path.join(outDir, 'assets/pragmata')

  try {
    await fs.mkdir(targetDir, { recursive: true })
    for (const [sourceName, targetName] of files) {
      await fs.copyFile(path.join(pragmataSourceDir, sourceName), path.join(targetDir, targetName))
    }
    return true
  } catch (error) {
    if (error?.code === 'ENOENT') {
      console.warn(`Pragmata Pro fonts not found in ${pragmataSourceDir}; code blocks will use the system monospace fallback.`)
      return false
    }
    throw error
  }
}

function stylesheet(hasPragmataAssets) {
  const pragmataFaces = hasPragmataAssets
    ? `@font-face{font-family:"Pragmata Pro";src:url("assets/pragmata/PragmataPro-Mono-Regular-Liga.ttf") format("truetype");font-weight:400;font-display:swap}
@font-face{font-family:"Pragmata Pro";src:url("assets/pragmata/PragmataPro-Mono-Bold-Liga.ttf") format("truetype");font-weight:700;font-display:swap}
`
    : ''

  return `@font-face{font-family:Inter;src:url("assets/fonts/Inter-Regular.woff2") format("woff2");font-weight:400;font-display:swap}
@font-face{font-family:Inter;src:url("assets/fonts/Inter-Medium.woff2") format("woff2");font-weight:500;font-display:swap}
@font-face{font-family:Inter;src:url("assets/fonts/Inter-SemiBold.woff2") format("woff2");font-weight:600;font-display:swap}
@font-face{font-family:Inter;src:url("assets/fonts/Inter-Bold.woff2") format("woff2");font-weight:700;font-display:swap}
${pragmataFaces}
:root{--bg:#fbfaf7;--paper:#fff;--ink:#202124;--muted:#68645f;--line:#ded7ca;--soft:#f2efe7;--soft2:#ece7dc;--accent:#246f74;--accent2:#8a4b2f;--ok:#2d6a4f;--shadow:0 14px 40px rgba(43,37,28,.08);font-family:Inter,system-ui,sans-serif;color:var(--ink);background:var(--bg)}
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:var(--bg);color:var(--ink);font-size:16px;line-height:1.6}a{color:var(--accent);text-underline-offset:.18em}code,pre,kbd,samp{font-family:"Pragmata Pro",ui-monospace,SFMono-Regular,Menlo,monospace;font-feature-settings:"liga" 1,"calt" 1}
.skip-link{position:absolute;left:16px;top:-40px;background:var(--ink);color:white;padding:8px 12px;z-index:10}.skip-link:focus{top:12px}
.topbar{position:sticky;top:0;z-index:5;display:flex;align-items:center;justify-content:space-between;gap:20px;padding:12px clamp(18px,4vw,56px);border-bottom:1px solid rgba(222,215,202,.9);background:rgba(251,250,247,.92);backdrop-filter:blur(14px)}
.brand{display:inline-flex;align-items:center;gap:10px;color:var(--ink);font-weight:700;text-decoration:none}.brand-mark{display:inline-grid;place-items:center;width:34px;height:34px;border-radius:7px;background:var(--ink);color:var(--bg);font-weight:700}
.topnav{display:flex;align-items:center;gap:4px;overflow-x:auto}.topnav a{padding:7px 10px;border-radius:7px;color:var(--muted);text-decoration:none;font-weight:700;white-space:nowrap}.topnav a.active,.topnav a:hover{background:var(--soft2);color:var(--ink)}
main{padding-bottom:72px}.hero,.doc-header{max-width:1120px;margin:0 auto;padding:clamp(54px,8vw,92px) clamp(20px,4vw,56px) 42px}.eyebrow,.card-kicker{margin:0 0 12px;color:var(--accent2);font-size:.76rem;font-weight:700;letter-spacing:0;text-transform:uppercase}
h1,h2,h3{margin:0;line-height:1.12;letter-spacing:0}h1{max-width:980px;font-size:clamp(2.35rem,5.8vw,5.2rem)}h2{font-size:clamp(1.65rem,3vw,2.45rem)}h3{font-size:1.08rem}.hero-copy,.doc-header p{max-width:820px;margin:22px 0 0;color:var(--muted);font-size:clamp(1rem,2vw,1.2rem)}
.hero-actions,.doc-actions,.section-actions{display:flex;flex-wrap:wrap;gap:10px;margin-top:28px}.button{display:inline-flex;align-items:center;justify-content:center;min-height:40px;padding:8px 14px;border:1px solid var(--line);border-radius:7px;background:var(--paper);color:var(--ink);text-decoration:none;font-weight:700;box-shadow:0 1px 0 rgba(0,0,0,.03)}.button.primary{background:var(--ink);border-color:var(--ink);color:var(--bg)}
.metric-grid{display:grid;grid-template-columns:repeat(6,minmax(0,1fr));gap:1px;max-width:1180px;margin:0 auto;padding:0 clamp(20px,4vw,56px) 56px}.metric{min-height:104px;padding:18px;background:var(--paper);border:1px solid var(--line)}.metric:first-child{border-radius:8px 0 0 8px}.metric:last-child{border-radius:0 8px 8px 0}.metric span{display:block;font-size:1.75rem;line-height:1;font-weight:700}.metric p{margin:10px 0 0;color:var(--muted);font-size:.86rem}.compact{padding-bottom:42px}
.split{display:grid;grid-template-columns:minmax(0,.78fr) minmax(0,1.22fr);gap:34px;align-items:center;max-width:1180px;margin:0 auto 64px;padding:0 clamp(20px,4vw,56px)}.split article p:not(.eyebrow){color:var(--muted)}
.diagram{margin:0;overflow:auto;padding:16px;border:1px solid var(--line);border-radius:8px;background:rgba(255,255,255,.66);box-shadow:var(--shadow)}.diagram svg{width:100%;height:auto;display:block;min-width:520px}.diagram.zoomable{position:relative;height:min(76vh,760px);min-height:420px;overflow:hidden;padding:0;touch-action:none;cursor:grab}.diagram.zoomable:active{cursor:grabbing}.diagram.zoomable svg{width:100%;height:100%;min-width:0;background:transparent}.diagram.zoomable.expanded{position:fixed;inset:18px;z-index:50;height:auto;min-height:0;border-radius:10px;background:var(--bg);box-shadow:0 28px 90px rgba(0,0,0,.35)}body.diagram-open{overflow:hidden}.diagram-toolbar{position:absolute;right:12px;top:12px;z-index:2;display:flex;gap:6px;padding:6px;border:1px solid var(--line);border-radius:8px;background:rgba(255,255,255,.9);backdrop-filter:blur(10px);box-shadow:0 8px 24px rgba(43,37,28,.12)}.diagram-toolbar button{display:inline-grid;place-items:center;width:34px;height:32px;border:1px solid var(--line);border-radius:7px;background:var(--paper);color:var(--ink);font:700 14px Inter,system-ui,sans-serif;cursor:pointer}.diagram-toolbar button[data-expand]{width:auto;padding:0 10px}.diagram-toolbar button:hover{background:var(--soft)}.diagram-hint{position:absolute;left:12px;bottom:10px;z-index:2;padding:4px 8px;border-radius:7px;background:rgba(255,255,255,.88);color:var(--muted);font-size:.78rem}.diagram-backdrop{position:fixed;inset:0;z-index:49;background:rgba(23,22,20,.52);backdrop-filter:blur(3px)}.diagram-error{white-space:pre-wrap;background:var(--soft);padding:18px;border-radius:8px}
.collection-band{max-width:1180px;margin:0 auto 64px;padding:0 clamp(20px,4vw,56px)}.collection-band.inset{margin-bottom:42px}.section-heading{margin-bottom:18px}.section-copy{max-width:780px;margin:10px 0 0;color:var(--muted)}
.collection-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px}.collection-card,.doc-card{border:1px solid var(--line);border-radius:8px;background:var(--paper);box-shadow:0 1px 0 rgba(0,0,0,.02)}.collection-card{display:block;min-height:190px;padding:22px;color:var(--ink);text-decoration:none}.collection-card span{color:var(--accent2);font-size:.76rem;font-weight:700;text-transform:uppercase}.collection-card strong{display:block;margin-top:12px;font-size:2.1rem}.collection-card p{color:var(--muted)}
.doc-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px}.doc-grid.compact-cards{grid-template-columns:repeat(3,minmax(0,1fr))}.doc-card{display:flex;flex-direction:column;min-height:286px;padding:22px}.doc-card h3 a{color:var(--ink);text-decoration:none}.doc-card h3 a:hover{color:var(--accent)}.doc-card p{color:var(--muted);margin:12px 0 auto}.card-stats{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin:20px 0 0}.card-stats div{min-width:0;padding:10px;border-radius:7px;background:var(--soft)}.card-stats dt{color:var(--muted);font-size:.7rem;font-weight:700;text-transform:uppercase}.card-stats dd{margin:2px 0 0;font-weight:700;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.toolbar{display:flex;align-items:center;gap:10px;margin-bottom:16px}.search-label{color:var(--muted);font-weight:700}input[type=search]{width:min(520px,100%);min-height:42px;padding:8px 12px;border:1px solid var(--line);border-radius:7px;background:var(--paper);color:var(--ink);font:inherit}
.doc-layout{display:grid;grid-template-columns:260px minmax(0,860px);gap:44px;justify-content:center;align-items:start;padding:0 clamp(20px,4vw,56px)}.toc{position:sticky;top:76px;max-height:calc(100vh - 100px);overflow:auto;padding:18px;border:1px solid var(--line);border-radius:8px;background:rgba(255,255,255,.72)}.toc-title{margin:0 0 10px;color:var(--muted);font-size:.78rem;font-weight:700;text-transform:uppercase}.toc nav{display:grid;gap:7px}.toc a{color:var(--muted);text-decoration:none;font-size:.88rem;line-height:1.3}.toc a:hover{color:var(--ink)}.toc-level-2{padding-left:8px}.toc-level-3{padding-left:18px}.toc-empty{color:var(--muted);font-size:.9rem}
.markdown-body{min-width:0;padding:36px;border:1px solid var(--line);border-radius:8px;background:var(--paper);box-shadow:var(--shadow)}.markdown-body h1{font-size:clamp(2rem,4vw,3.4rem)}.markdown-body h2{margin-top:2.2em;padding-top:.7em;border-top:1px solid var(--line);font-size:1.75rem}.markdown-body h3{margin-top:1.8em;font-size:1.22rem}.markdown-body p,.markdown-body li{color:#36332f}.markdown-body blockquote{margin:24px 0;padding:12px 18px;border-left:4px solid var(--accent);background:var(--soft)}.markdown-body table{width:100%;border-collapse:collapse;margin:24px 0;font-size:.95rem}.markdown-body th,.markdown-body td{padding:10px 12px;border:1px solid var(--line);text-align:left;vertical-align:top}.markdown-body th{background:var(--soft)}.markdown-body code:not(pre code){padding:.08em .28em;border-radius:5px;background:var(--soft);font-size:.9em}.markdown-body pre{overflow:auto;margin:24px 0;border:1px solid var(--line);border-radius:8px}.markdown-body .shiki{padding:18px;background:#f7f5ef!important}.markdown-body .anchor-link{margin-left:8px;color:var(--line);text-decoration:none;opacity:0}.markdown-body h1:hover .anchor-link,.markdown-body h2:hover .anchor-link,.markdown-body h3:hover .anchor-link{opacity:1}
.pager{display:flex;justify-content:space-between;gap:16px;max-width:1180px;margin:34px auto 0;padding:0 clamp(20px,4vw,56px)}
@media (max-width:1000px){.metric-grid,.collection-grid,.doc-grid,.doc-grid.compact-cards,.split,.doc-layout{grid-template-columns:1fr}.metric,.metric:first-child,.metric:last-child{border-radius:8px}.toc{position:static;max-height:none}.diagram svg{min-width:430px}.markdown-body{padding:24px}}
@media (max-width:640px){.topbar{align-items:flex-start;flex-direction:column;gap:10px}h1{font-size:2.3rem}.hero,.doc-header{padding-top:40px}.hero-actions,.doc-actions,.pager{flex-direction:column;align-items:stretch}.markdown-body{padding:18px}}`
}

function clientScript() {
  return `const input = document.querySelector('#doc-search')
const cards = [...document.querySelectorAll('[data-doc-card]')]
if (input) {
  input.addEventListener('input', () => {
    const query = input.value.trim().toLowerCase()
    for (const card of cards) card.hidden = query && !card.dataset.search.includes(query)
  })
}

for (const figure of document.querySelectorAll('figure.diagram')) {
  const svg = figure.querySelector('svg')
  if (!svg || !svg.viewBox || !svg.viewBox.baseVal) continue
  const initial = svg.viewBox.baseVal
  const state = { x: initial.x, y: initial.y, w: initial.width, h: initial.height }
  const home = { ...state }
  const minW = home.w / 24
  const maxW = home.w * 16
  let drag = null
  let expanded = false
  let placeholder = null
  let backdrop = null

  figure.classList.add('zoomable')
  figure.tabIndex = 0
  figure.setAttribute('role', 'region')
  figure.setAttribute('aria-label', 'Zoomable diagram. Wheel or pinch to zoom, drag to pan.')
  figure.insertAdjacentHTML('afterbegin', '<div class="diagram-toolbar" aria-label="Diagram controls"><button type="button" data-zoom="in" title="Zoom in">+</button><button type="button" data-zoom="out" title="Zoom out">-</button><button type="button" data-zoom="fit" title="Fit diagram">Fit</button><button type="button" data-expand title="Expand diagram">Expand</button></div><div class="diagram-hint">Wheel zoom · drag pan · double-click fit</div>')

  const apply = () => svg.setAttribute('viewBox', [state.x, state.y, state.w, state.h].join(' '))
  const clamp = () => {
    if (state.w < minW) {
      const cx = state.x + state.w / 2
      const cy = state.y + state.h / 2
      state.w = minW
      state.h = minW * home.h / home.w
      state.x = cx - state.w / 2
      state.y = cy - state.h / 2
    }
    if (state.w > maxW) {
      const cx = state.x + state.w / 2
      const cy = state.y + state.h / 2
      state.w = maxW
      state.h = maxW * home.h / home.w
      state.x = cx - state.w / 2
      state.y = cy - state.h / 2
    }
  }
  const point = (event) => {
    const rect = svg.getBoundingClientRect()
    return {
      x: state.x + ((event.clientX - rect.left) / rect.width) * state.w,
      y: state.y + ((event.clientY - rect.top) / rect.height) * state.h,
    }
  }
  const zoomAt = (factor, event) => {
    const p = event ? point(event) : { x: state.x + state.w / 2, y: state.y + state.h / 2 }
    const nextW = state.w / factor
    const nextH = state.h / factor
    state.x = p.x - ((p.x - state.x) / state.w) * nextW
    state.y = p.y - ((p.y - state.y) / state.h) * nextH
    state.w = nextW
    state.h = nextH
    clamp()
    apply()
  }
  const fit = () => {
    Object.assign(state, home)
    apply()
  }
  const expandButton = figure.querySelector('[data-expand]')
  const openExpanded = () => {
    if (expanded) return
    expanded = true
    placeholder = document.createComment('diagram-placeholder')
    backdrop = document.createElement('div')
    backdrop.className = 'diagram-backdrop'
    figure.after(placeholder)
    document.body.append(backdrop, figure)
    document.body.classList.add('diagram-open')
    figure.classList.add('expanded')
    expandButton.textContent = 'Close'
    expandButton.title = 'Close expanded diagram'
    figure.focus({ preventScroll: true })
  }
  const closeExpanded = () => {
    if (!expanded) return
    expanded = false
    placeholder.replaceWith(figure)
    backdrop.remove()
    placeholder = null
    backdrop = null
    document.body.classList.remove('diagram-open')
    figure.classList.remove('expanded')
    expandButton.textContent = 'Expand'
    expandButton.title = 'Expand diagram'
  }

  figure.querySelector('[data-zoom="in"]').addEventListener('click', () => zoomAt(1.35))
  figure.querySelector('[data-zoom="out"]').addEventListener('click', () => zoomAt(1 / 1.35))
  figure.querySelector('[data-zoom="fit"]').addEventListener('click', fit)
  expandButton.addEventListener('click', () => expanded ? closeExpanded() : openExpanded())
  figure.addEventListener('dblclick', fit)
  figure.addEventListener('wheel', (event) => {
    event.preventDefault()
    zoomAt(Math.exp(-event.deltaY * 0.0012), event)
  }, { passive: false })
  figure.addEventListener('pointerdown', (event) => {
    if (event.target.closest('.diagram-toolbar')) return
    figure.setPointerCapture(event.pointerId)
    drag = { id: event.pointerId, x: event.clientX, y: event.clientY, ox: state.x, oy: state.y }
  })
  figure.addEventListener('pointermove', (event) => {
    if (!drag || drag.id !== event.pointerId) return
    const rect = svg.getBoundingClientRect()
    state.x = drag.ox - ((event.clientX - drag.x) / rect.width) * state.w
    state.y = drag.oy - ((event.clientY - drag.y) / rect.height) * state.h
    apply()
  })
  figure.addEventListener('pointerup', () => { drag = null })
  figure.addEventListener('pointercancel', () => { drag = null })
  figure.addEventListener('keydown', (event) => {
    if (event.key === '+' || event.key === '=') zoomAt(1.25)
    if (event.key === '-' || event.key === '_') zoomAt(1 / 1.25)
    if (event.key === '0') fit()
    if (event.key === 'Escape') closeExpanded()
  })
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') closeExpanded()
  })
  apply()
}`
}
