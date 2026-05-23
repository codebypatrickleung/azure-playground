<template>
  <div class="app">

    <!-- ── Header ─────────────────────────────────────────── -->
    <header class="app-header">
      <div class="header-inner">
        <div class="brand">
          <span class="brand-icon">📰</span>
          <div>
            <h1>Technical News</h1>
            <p>Filtered and summarised by AI</p>
          </div>
        </div>
        <div class="header-badge">
          <span class="badge-dot"></span>
          Azure OpenAI · LangGraph
        </div>
      </div>
    </header>

    <!-- ── Main ───────────────────────────────────────────── -->
    <main class="app-main">

      <!-- Search card -->
      <div class="search-card">
        <div class="search-bar" :class="{ focused: searchFocused }">
          <svg class="search-icon" viewBox="0 0 20 20" fill="none">
            <circle cx="8.5" cy="8.5" r="5.5" stroke="currentColor" stroke-width="1.6"/>
            <path d="M13 13l3.5 3.5" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>
          </svg>
          <input
            ref="searchInput"
            v-model="topic"
            type="text"
            placeholder="Search topic — e.g. Kubernetes, Azure, LLMs"
            @keyup.enter="searchNews"
            @focus="searchFocused = true"
            @blur="searchFocused = false"
          />
          <button class="btn-primary" @click="searchNews" :disabled="!topic.trim() || loading">
            <span v-if="!loading">Search</span>
            <span v-else class="btn-spinner"></span>
          </button>
        </div>

        <div class="category-row">
          <span class="filter-label">Filter</span>
          <label
            v-for="cat in availableCategories"
            :key="cat.id"
            class="chip"
            :class="{ active: selectedCategories.includes(cat.id) }"
          >
            <input type="checkbox" :value="cat.id" v-model="selectedCategories" hidden />
            <span class="chip-icon">{{ cat.icon }}</span>
            {{ cat.label }}
          </label>
        </div>
      </div>

      <!-- Pipeline steps -->
      <Transition name="fade">
        <div v-if="loading" class="pipeline">
          <div
            v-for="(step, i) in steps"
            :key="step.label"
            class="pipeline-step"
            :class="{ active: step.active, done: step.done }"
          >
            <div class="step-circle">
              <svg v-if="step.done" viewBox="0 0 16 16" fill="none">
                <path d="M3 8l3.5 3.5L13 5" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
              </svg>
              <span v-else-if="step.active" class="step-pulse"></span>
              <span v-else>{{ i + 1 }}</span>
            </div>
            <span class="step-label">{{ step.label }}</span>
            <div v-if="i < steps.length - 1" class="step-connector" :class="{ done: step.done }"></div>
          </div>
        </div>
      </Transition>

      <!-- Skeleton grid -->
      <div v-if="loading" class="article-grid">
        <div v-for="i in 6" :key="i" class="skeleton-card">
          <div class="skeleton-meta">
            <div class="skeleton w-20"></div>
            <div class="skeleton w-16"></div>
            <div class="skeleton w-10 ml-auto"></div>
          </div>
          <div class="skeleton w-full h-5 mt-3"></div>
          <div class="skeleton w-3/4 h-5 mt-2"></div>
          <div class="skeleton w-full h-3 mt-4"></div>
          <div class="skeleton w-full h-3 mt-2"></div>
          <div class="skeleton w-2/3 h-3 mt-2"></div>
          <div class="skeleton w-24 h-8 mt-4 ml-auto"></div>
        </div>
      </div>

      <!-- Error -->
      <Transition name="fade">
        <div v-if="error && !loading" class="state-card error-state">
          <div class="state-icon">⚠️</div>
          <h2>Something went wrong</h2>
          <p>{{ error }}</p>
          <button class="btn-ghost" @click="error = ''">Dismiss</button>
        </div>
      </Transition>

      <!-- Welcome state -->
      <Transition name="fade">
        <div v-if="!loading && !error && !hasSearched" class="state-card welcome-state">
          <div class="state-icon">🔍</div>
          <h2>What are you following today?</h2>
          <p>Enter a topic above, select your areas of interest, and let the AI filter and summarise the latest news for you.</p>
          <div class="hint-row">
            <span class="hint-chip">Kubernetes 1.34</span>
            <span class="hint-chip">Azure AI Foundry</span>
            <span class="hint-chip">LangGraph agents</span>
            <span class="hint-chip">Terraform 2.0</span>
          </div>
        </div>
      </Transition>

      <!-- Empty state -->
      <Transition name="fade">
        <div v-if="!loading && !error && hasSearched && !articles.length" class="state-card">
          <div class="state-icon">📭</div>
          <h2>No results found</h2>
          <p>Try a different topic or adjust your category filters.</p>
        </div>
      </Transition>

      <!-- Results -->
      <template v-if="!loading && articles.length">
        <div class="results-header">
          <span class="results-count">{{ articles.length }} article{{ articles.length !== 1 ? 's' : '' }}</span>
          <span class="results-topic">for "{{ lastTopic }}"</span>
        </div>

        <TransitionGroup name="list" tag="div" class="article-grid">
          <article
            v-for="article in articles"
            :key="article.url"
            class="article-card"
            :class="{ 'is-selected': selectedArticle?.url === article.url }"
          >
            <div class="card-meta">
              <span class="source-chip">{{ article.source }}</span>
              <span class="card-date">{{ formatDate(article.published_at) }}</span>
              <span
                v-if="article.relevance_score"
                class="score-badge"
                :class="scoreClass(article.relevance_score)"
              >{{ article.relevance_score }}/10</span>
            </div>

            <h2 class="card-title">
              <a :href="article.url" target="_blank" rel="noopener noreferrer">
                {{ article.title }}
              </a>
            </h2>

            <p class="card-summary">{{ article.summary || article.description }}</p>

            <div class="card-footer">
              <a :href="article.url" target="_blank" rel="noopener noreferrer" class="read-link">
                Read original ↗
              </a>
              <button class="btn-outline" @click="selectArticle(article)">
                Deep Dive
              </button>
            </div>
          </article>
        </TransitionGroup>
      </template>

    </main>
  </div>

  <!-- ── Deep dive panel (teleported to body) ───────────── -->
  <Teleport to="body">
    <Transition name="overlay">
      <div v-if="selectedArticle" class="panel-overlay" @click.self="closePanel"></div>
    </Transition>
    <Transition name="panel">
      <div v-if="selectedArticle" class="deep-dive-panel" role="dialog" aria-modal="true">

        <div class="panel-header">
          <div>
            <p class="panel-eyebrow">Deep Dive</p>
            <h2 class="panel-title">{{ selectedArticle.title }}</h2>
            <a :href="selectedArticle.url" target="_blank" rel="noopener noreferrer" class="panel-link">
              {{ selectedArticle.source }} ↗
            </a>
          </div>
          <button class="close-btn" @click="closePanel" aria-label="Close panel">
            <svg viewBox="0 0 20 20" fill="none">
              <path d="M5 5l10 10M15 5L5 15" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
            </svg>
          </button>
        </div>

        <div class="panel-divider"></div>

        <div class="panel-body">
          <p class="panel-prompt">Ask a follow-up question about this article</p>

          <div class="question-bar">
            <input
              v-model="followUpQuestion"
              type="text"
              placeholder="e.g. What does this mean for AKS users?"
              @keyup.enter="askFollowUp"
            />
            <button class="btn-primary" @click="askFollowUp" :disabled="!followUpQuestion.trim() || deepDiveLoading">
              <span v-if="!deepDiveLoading">Ask</span>
              <span v-else class="btn-spinner"></span>
            </button>
          </div>

          <Transition name="fade">
            <div v-if="deepDiveAnswer" class="answer-card">
              <div class="answer-label">
                <svg viewBox="0 0 16 16" fill="none">
                  <circle cx="8" cy="8" r="6.5" stroke="currentColor" stroke-width="1.4"/>
                  <path d="M8 5v4M8 11v.5" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>
                </svg>
                Answer
              </div>
              <p class="answer-text">{{ deepDiveAnswer }}</p>
            </div>
          </Transition>
        </div>

      </div>
    </Transition>
  </Teleport>
</template>

<script setup>
import { ref, reactive } from 'vue'

const LLM_SERVICE_URL = import.meta.env.VITE_LLM_SERVICE_URL || '/api'

// ── State ────────────────────────────────────────────────
const topic            = ref('')
const lastTopic        = ref('')
const hasSearched      = ref(false)
const searchFocused    = ref(false)
const articles         = ref([])
const loading          = ref(false)
const error            = ref('')

const selectedArticle  = ref(null)
const followUpQuestion = ref('')
const deepDiveLoading  = ref(false)
const deepDiveAnswer   = ref('')

// ── Categories ───────────────────────────────────────────
const availableCategories = [
  { id: 'Cloud & Infrastructure',    label: 'Cloud & Infra',    icon: '☁️' },
  { id: 'Kubernetes & Containers',   label: 'Kubernetes',       icon: '⚙️' },
  { id: 'AI & LLMs',                 label: 'AI & LLMs',        icon: '🤖' },
  { id: 'Cybersecurity',             label: 'Security',         icon: '🔒' },
  { id: 'Programming Languages',     label: 'Dev',              icon: '💻' },
]
const selectedCategories = ref([
  'Cloud & Infrastructure',
  'Kubernetes & Containers',
  'AI & LLMs',
])

// ── Pipeline steps ───────────────────────────────────────
const steps = reactive([
  { label: 'Fetching news',       active: false, done: false },
  { label: 'Filtering relevance', active: false, done: false },
  { label: 'Summarising',         active: false, done: false },
])

function resetSteps() {
  steps.forEach(s => { s.active = false; s.done = false })
}

async function animateSteps() {
  for (const step of steps) {
    step.active = true
    await new Promise(r => setTimeout(r, 900))
    step.done = true
    step.active = false
  }
}

// ── Search ───────────────────────────────────────────────
async function searchNews() {
  const q = topic.value.trim()
  if (!q || loading.value) return

  error.value     = ''
  articles.value  = []
  selectedArticle.value = null
  deepDiveAnswer.value  = ''
  loading.value   = true
  hasSearched.value = true
  lastTopic.value = q
  resetSteps()

  const stepAnimation = animateSteps()

  try {
    const res = await fetch(`${LLM_SERVICE_URL}/news/search`, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify({ topic: q, categories: selectedCategories.value }),
    })
    if (!res.ok) {
      const data = await res.json().catch(() => ({}))
      throw new Error(data.detail || `Request failed (${res.status})`)
    }
    await stepAnimation
    articles.value = await res.json()
  } catch (err) {
    error.value = err?.message || 'Unknown error'
  } finally {
    loading.value = false
    resetSteps()
  }
}

// ── Deep dive ────────────────────────────────────────────
function selectArticle(article) {
  selectedArticle.value  = article
  followUpQuestion.value = ''
  deepDiveAnswer.value   = ''
}

function closePanel() {
  selectedArticle.value = null
}

async function askFollowUp() {
  const q = followUpQuestion.value.trim()
  if (!q || deepDiveLoading.value) return

  deepDiveLoading.value = true
  deepDiveAnswer.value  = ''

  try {
    const res = await fetch(`${LLM_SERVICE_URL}/news/deep-dive`, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify({
        url:         selectedArticle.value.url,
        title:       selectedArticle.value.title,
        description: selectedArticle.value.description,
        question:    q,
      }),
    })
    if (!res.ok) {
      const data = await res.json().catch(() => ({}))
      throw new Error(data.detail || `Request failed (${res.status})`)
    }
    const data = await res.json()
    deepDiveAnswer.value = data.answer
  } catch (err) {
    deepDiveAnswer.value = `Error: ${err?.message || 'Unknown error'}`
  } finally {
    deepDiveLoading.value = false
  }
}

// ── Helpers ──────────────────────────────────────────────
function formatDate(iso) {
  if (!iso) return ''
  return new Date(iso).toLocaleDateString('en-GB', {
    day: 'numeric', month: 'short', year: 'numeric',
  })
}

function scoreClass(score) {
  if (score >= 9) return 'score-high'
  if (score >= 7) return 'score-mid'
  return 'score-low'
}
</script>

<style scoped>
/* ── Layout ───────────────────────────────────────────── */
.app {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
}

.app-main {
  flex: 1;
  max-width: 1100px;
  width: 100%;
  margin: 0 auto;
  padding: 2rem 1.5rem 4rem;
}

/* ── Header ───────────────────────────────────────────── */
.app-header {
  background: linear-gradient(135deg, #0f172a 0%, #1e3a5f 100%);
  padding: 1.25rem 0;
  position: sticky;
  top: 0;
  z-index: 50;
  border-bottom: 1px solid rgba(255,255,255,0.06);
}

.header-inner {
  max-width: 1100px;
  margin: 0 auto;
  padding: 0 1.5rem;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
}

.brand {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}

.brand-icon {
  font-size: 1.6rem;
  line-height: 1;
}

.brand h1 {
  font-size: 1.1rem;
  font-weight: 700;
  color: #f8fafc;
  letter-spacing: -0.01em;
}

.brand p {
  font-size: 0.75rem;
  color: #94a3b8;
  margin-top: 0.1rem;
}

.header-badge {
  display: flex;
  align-items: center;
  gap: 0.45rem;
  font-size: 0.75rem;
  color: #94a3b8;
  background: rgba(255,255,255,0.06);
  border: 1px solid rgba(255,255,255,0.1);
  border-radius: var(--radius-xl);
  padding: 0.3rem 0.75rem;
}

.badge-dot {
  width: 6px;
  height: 6px;
  background: #34d399;
  border-radius: 50%;
  animation: pulse-dot 2s ease-in-out infinite;
}

@keyframes pulse-dot {
  0%, 100% { opacity: 1; }
  50%       { opacity: 0.4; }
}

/* ── Search card ──────────────────────────────────────── */
.search-card {
  background: var(--surface);
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-md);
  padding: 1.25rem;
  margin-bottom: 1.5rem;
}

.search-bar {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  border: 1.5px solid var(--border);
  border-radius: var(--radius-md);
  padding: 0.5rem 0.5rem 0.5rem 1rem;
  transition: border-color var(--ease), box-shadow var(--ease);
  margin-bottom: 1rem;
}

.search-bar.focused {
  border-color: var(--primary);
  box-shadow: 0 0 0 3px var(--primary-light);
}

.search-icon {
  width: 18px;
  height: 18px;
  color: var(--text-subtle);
  flex-shrink: 0;
}

.search-bar input {
  flex: 1;
  border: none;
  outline: none;
  font-size: 0.9375rem;
  color: var(--text-heading);
  background: transparent;
}

.search-bar input::placeholder { color: var(--text-subtle); }

/* ── Buttons ──────────────────────────────────────────── */
.btn-primary {
  background: var(--primary);
  color: #fff;
  border: none;
  padding: 0.5rem 1.25rem;
  border-radius: var(--radius-sm);
  font-size: 0.875rem;
  font-weight: 600;
  cursor: pointer;
  transition: background var(--ease);
  display: flex;
  align-items: center;
  justify-content: center;
  min-width: 80px;
  height: 38px;
}

.btn-primary:hover:not(:disabled) { background: var(--primary-hover); }
.btn-primary:disabled { background: var(--text-subtle); cursor: not-allowed; }

.btn-outline {
  background: none;
  border: 1.5px solid var(--primary);
  color: var(--primary);
  padding: 0.35rem 0.9rem;
  border-radius: var(--radius-sm);
  font-size: 0.8125rem;
  font-weight: 500;
  cursor: pointer;
  transition: all var(--ease);
}

.btn-outline:hover {
  background: var(--primary);
  color: #fff;
}

.btn-ghost {
  background: none;
  border: 1.5px solid var(--border);
  color: var(--text-muted);
  padding: 0.45rem 1.1rem;
  border-radius: var(--radius-sm);
  font-size: 0.875rem;
  font-weight: 500;
  cursor: pointer;
  transition: all var(--ease);
}

.btn-ghost:hover { border-color: var(--text-muted); color: var(--text-body); }

/* Spinner inside button */
.btn-spinner {
  width: 16px;
  height: 16px;
  border: 2px solid rgba(255,255,255,0.4);
  border-top-color: #fff;
  border-radius: 50%;
  animation: spin 0.7s linear infinite;
  display: inline-block;
}

@keyframes spin { to { transform: rotate(360deg); } }

/* ── Category chips ───────────────────────────────────── */
.category-row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.5rem;
}

.filter-label {
  font-size: 0.75rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--text-subtle);
  margin-right: 0.25rem;
}

.chip {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  padding: 0.3rem 0.75rem;
  border: 1.5px solid var(--border);
  border-radius: var(--radius-xl);
  font-size: 0.8125rem;
  font-weight: 500;
  color: var(--text-muted);
  cursor: pointer;
  user-select: none;
  transition: all var(--ease);
  background: var(--surface);
}

.chip:hover { border-color: var(--primary-muted); color: var(--primary); }

.chip.active {
  background: var(--primary-light);
  border-color: var(--primary);
  color: var(--primary);
}

.chip-icon { font-size: 0.85rem; line-height: 1; }

/* ── Pipeline steps ───────────────────────────────────── */
.pipeline {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0;
  padding: 1.5rem 0;
  margin-bottom: 0.5rem;
}

.pipeline-step {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  color: var(--text-subtle);
  font-size: 0.8125rem;
  font-weight: 500;
  transition: color var(--ease);
}

.pipeline-step.active { color: var(--primary); }
.pipeline-step.done   { color: var(--green); }

.step-circle {
  width: 28px;
  height: 28px;
  border-radius: 50%;
  border: 2px solid currentColor;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 0.75rem;
  font-weight: 600;
  flex-shrink: 0;
  transition: all var(--ease);
  background: var(--surface);
}

.pipeline-step.done .step-circle {
  background: var(--green-bg);
  border-color: var(--green);
}

.pipeline-step.done .step-circle svg {
  width: 14px;
  height: 14px;
  color: var(--green);
}

.step-pulse {
  width: 10px;
  height: 10px;
  background: var(--primary);
  border-radius: 50%;
  animation: pulse-step 1s ease-in-out infinite;
}

@keyframes pulse-step {
  0%, 100% { transform: scale(1);   opacity: 1; }
  50%       { transform: scale(0.6); opacity: 0.5; }
}

.step-connector {
  width: 48px;
  height: 2px;
  background: var(--border);
  margin: 0 0.5rem;
  flex-shrink: 0;
  transition: background 0.4s ease;
}

.step-connector.done { background: var(--green); }

/* ── Skeleton ─────────────────────────────────────────── */
@keyframes shimmer {
  0%   { background-position: -400px 0; }
  100% { background-position:  400px 0; }
}

.skeleton {
  background: linear-gradient(90deg, #e2e8f0 25%, #f1f5f9 50%, #e2e8f0 75%);
  background-size: 800px 100%;
  animation: shimmer 1.4s ease-in-out infinite;
  border-radius: var(--radius-sm);
  height: 12px;
}

.skeleton.h-3  { height: 12px; }
.skeleton.h-5  { height: 20px; }
.skeleton.h-8  { height: 32px; }
.skeleton.w-10 { width: 40px; }
.skeleton.w-16 { width: 64px; }
.skeleton.w-20 { width: 80px; }
.skeleton.w-24 { width: 96px; }
.skeleton.w-full  { width: 100%; }
.skeleton.w-3\/4  { width: 75%; }
.skeleton.w-2\/3  { width: 66%; }
.skeleton.ml-auto { margin-left: auto; }
.skeleton.mt-2 { margin-top: 0.5rem; }
.skeleton.mt-3 { margin-top: 0.75rem; }
.skeleton.mt-4 { margin-top: 1rem; }

.skeleton-card {
  background: var(--surface);
  border-radius: var(--radius-lg);
  padding: 1.25rem;
  box-shadow: var(--shadow-sm);
}

.skeleton-meta {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.skeleton-meta .skeleton { height: 20px; border-radius: var(--radius-xl); }

/* ── State cards ──────────────────────────────────────── */
.state-card {
  background: var(--surface);
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-sm);
  padding: 3rem 2rem;
  text-align: center;
  margin-top: 1rem;
}

.state-icon {
  font-size: 2.5rem;
  margin-bottom: 1rem;
  line-height: 1;
}

.state-card h2 {
  font-size: 1.1rem;
  font-weight: 600;
  color: var(--text-heading);
  margin-bottom: 0.5rem;
}

.state-card p {
  color: var(--text-muted);
  font-size: 0.9rem;
  max-width: 360px;
  margin: 0 auto 1.5rem;
}

.error-state { border-top: 3px solid var(--red); }
.error-state h2 { color: var(--red); }
.error-state p { color: var(--text-body); }

.hint-row {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  justify-content: center;
}

.hint-chip {
  padding: 0.3rem 0.8rem;
  border: 1.5px dashed var(--border);
  border-radius: var(--radius-xl);
  font-size: 0.8rem;
  color: var(--text-muted);
  cursor: pointer;
  transition: all var(--ease);
}

.hint-chip:hover {
  border-color: var(--primary);
  color: var(--primary);
  border-style: solid;
}

/* ── Results ──────────────────────────────────────────── */
.results-header {
  display: flex;
  align-items: baseline;
  gap: 0.5rem;
  margin-bottom: 1rem;
  padding: 0 0.25rem;
}

.results-count {
  font-size: 0.875rem;
  font-weight: 600;
  color: var(--text-heading);
}

.results-topic {
  font-size: 0.875rem;
  color: var(--text-muted);
}

/* ── Article grid ─────────────────────────────────────── */
.article-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 1rem;
}

@media (max-width: 680px) {
  .article-grid { grid-template-columns: 1fr; }
}

/* ── Article card ─────────────────────────────────────── */
.article-card {
  background: var(--surface);
  border-radius: var(--radius-lg);
  padding: 1.25rem;
  box-shadow: var(--shadow-sm);
  border: 1.5px solid transparent;
  display: flex;
  flex-direction: column;
  gap: 0;
  transition: box-shadow var(--ease), border-color var(--ease), transform var(--ease);
}

.article-card:hover {
  box-shadow: var(--shadow-md);
  transform: translateY(-1px);
}

.article-card.is-selected {
  border-color: var(--primary);
  box-shadow: 0 0 0 3px var(--primary-light), var(--shadow-md);
}

.card-meta {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin-bottom: 0.75rem;
  flex-wrap: wrap;
}

.source-chip {
  font-size: 0.75rem;
  font-weight: 600;
  padding: 0.2rem 0.6rem;
  border-radius: var(--radius-xl);
  background: var(--primary-light);
  color: var(--primary);
  letter-spacing: 0.01em;
}

.card-date {
  font-size: 0.75rem;
  color: var(--text-subtle);
}

.score-badge {
  margin-left: auto;
  font-size: 0.75rem;
  font-weight: 700;
  padding: 0.15rem 0.55rem;
  border-radius: var(--radius-xl);
}

.score-high { background: var(--green-bg); color: var(--green); }
.score-mid  { background: var(--amber-bg); color: var(--amber); }
.score-low  { background: #f1f5f9;         color: var(--text-muted); }

.card-title {
  font-size: 0.9375rem;
  font-weight: 600;
  line-height: 1.4;
  color: var(--text-heading);
  letter-spacing: -0.01em;
  margin-bottom: 0.6rem;
  flex: 1;
}

.card-title a:hover { color: var(--primary); }

.card-summary {
  font-size: 0.875rem;
  color: var(--text-muted);
  line-height: 1.6;
  margin-bottom: 1rem;
  display: -webkit-box;
  -webkit-line-clamp: 3;
  -webkit-box-orient: vertical;
  overflow: hidden;
  flex: 1;
}

.card-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-top: auto;
}

.read-link {
  font-size: 0.8rem;
  color: var(--text-subtle);
  transition: color var(--ease);
}

.read-link:hover { color: var(--primary); }

/* ── Panel overlay ────────────────────────────────────── */
.panel-overlay {
  position: fixed;
  inset: 0;
  background: rgba(15, 23, 42, 0.45);
  backdrop-filter: blur(3px);
  z-index: 100;
}

/* ── Deep dive panel ──────────────────────────────────── */
.deep-dive-panel {
  position: fixed;
  top: 0;
  right: 0;
  bottom: 0;
  width: 480px;
  max-width: 100vw;
  background: var(--surface);
  box-shadow: var(--shadow-xl);
  z-index: 101;
  display: flex;
  flex-direction: column;
  overflow-y: auto;
}

.panel-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 1rem;
  padding: 1.75rem 1.75rem 1.25rem;
  position: sticky;
  top: 0;
  background: var(--surface);
  z-index: 1;
}

.panel-eyebrow {
  font-size: 0.7rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--primary);
  margin-bottom: 0.4rem;
}

.panel-title {
  font-size: 1rem;
  font-weight: 600;
  color: var(--text-heading);
  line-height: 1.4;
  letter-spacing: -0.01em;
  margin-bottom: 0.4rem;
}

.panel-link {
  font-size: 0.8rem;
  color: var(--text-subtle);
  transition: color var(--ease);
}
.panel-link:hover { color: var(--primary); }

.close-btn {
  background: var(--surface-raised);
  border: 1.5px solid var(--border);
  border-radius: var(--radius-md);
  width: 34px;
  height: 34px;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  flex-shrink: 0;
  transition: all var(--ease);
}

.close-btn:hover { background: var(--red-bg); border-color: var(--red); }
.close-btn svg { width: 16px; height: 16px; color: var(--text-muted); }
.close-btn:hover svg { color: var(--red); }

.panel-divider {
  height: 1px;
  background: var(--border);
  margin: 0 1.75rem;
}

.panel-body {
  padding: 1.5rem 1.75rem 2rem;
  flex: 1;
}

.panel-prompt {
  font-size: 0.8125rem;
  font-weight: 600;
  color: var(--text-muted);
  margin-bottom: 0.75rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.question-bar {
  display: flex;
  gap: 0.6rem;
  margin-bottom: 1.25rem;
}

.question-bar input {
  flex: 1;
  padding: 0.6rem 0.875rem;
  border: 1.5px solid var(--border);
  border-radius: var(--radius-md);
  font-size: 0.9rem;
  color: var(--text-body);
  background: var(--surface-raised);
  outline: none;
  transition: border-color var(--ease);
}

.question-bar input:focus {
  border-color: var(--primary);
  background: var(--surface);
}

.answer-card {
  background: var(--surface-raised);
  border: 1.5px solid var(--border);
  border-radius: var(--radius-md);
  padding: 1.1rem;
}

.answer-label {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  font-size: 0.75rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--primary);
  margin-bottom: 0.6rem;
}

.answer-label svg {
  width: 14px;
  height: 14px;
}

.answer-text {
  font-size: 0.9rem;
  line-height: 1.7;
  color: var(--text-body);
  white-space: pre-wrap;
}

/* ── Transitions ──────────────────────────────────────── */
.fade-enter-active, .fade-leave-active { transition: opacity 0.22s ease; }
.fade-enter-from,  .fade-leave-to      { opacity: 0; }

.overlay-enter-active, .overlay-leave-active { transition: opacity 0.25s ease; }
.overlay-enter-from,   .overlay-leave-to     { opacity: 0; }

.panel-enter-active, .panel-leave-active { transition: transform 0.28s cubic-bezier(0.4,0,0.2,1); }
.panel-enter-from,   .panel-leave-to     { transform: translateX(100%); }

.list-enter-active {
  transition: all 0.3s ease;
  transition-delay: calc(var(--i, 0) * 0.05s);
}
.list-enter-from { opacity: 0; transform: translateY(10px); }
.list-leave-active { transition: all 0.2s ease; position: absolute; }
.list-leave-to     { opacity: 0; }
</style>
