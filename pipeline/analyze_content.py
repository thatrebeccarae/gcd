#!/usr/bin/env python3
"""
Content Quality Analyzer — 5-Category, 100-Point Scoring System

Analyzes markdown content drafts for quality, SEO, E-E-A-T signals, AEO/GEO
readiness, and anti-AI detection. Returns structured JSON scorecards for
reviewer agent consumption.

Usage:
    python analyze_content.py <file>                    # JSON output
    python analyze_content.py <file> --format markdown  # Markdown report
    python analyze_content.py <file> --format table     # Compact table
    python analyze_content.py --batch <directory>        # Batch mode
    python analyze_content.py --batch <dir> --sort score # Sorted batch
    python analyze_content.py <file> --fix               # Prioritized fixes

Scoring:
    Content Quality       30 pts   Depth, readability, originality, structure, engagement, grammar
    SEO Optimization      20 pts   Headings, title, keywords, linking, meta
    E-E-A-T Signals       15 pts   Author, citations, trust, experience
    AEO/GEO Readiness     20 pts   Answer-first, citability, capsules, entities, FAQ
    Anti-AI Detection     15 pts   Burstiness, banned phrases, TTR, passive, triggers

Bands:
    90-100  Exceptional
    80-89   Strong
    70-79   Acceptable
    60-69   Below Standard
    <60     Rewrite

Optional dependencies (graceful degradation):
    pip install textstat
"""

import argparse
import json
import math
import re
import sys
from pathlib import Path
from typing import Any


# ---------------------------------------------------------------------------
# Optional dependency detection
# ---------------------------------------------------------------------------

try:
    import textstat
    HAS_TEXTSTAT = True
except ImportError:
    HAS_TEXTSTAT = False


def _print_dependency_notice() -> None:
    """Print missing-dependency notice to stderr so JSON output stays clean."""
    if not HAS_TEXTSTAT:
        print(
            "Note: Optional dependency 'textstat' not found. "
            "Flesch score will be estimated. Install with: pip install textstat",
            file=sys.stderr,
        )


# ---------------------------------------------------------------------------
# AI content detection phrases (from ai-detection-rules.md)
# ---------------------------------------------------------------------------

# 16 banned phrases -- zero tolerance
BANNED_PHRASES = [
    "in today's digital landscape",
    "it's important to note",
    "in conclusion",
    "dive into",
    "deep dive",
    "game-changer",
    "navigate the landscape",
    "revolutionize",
    "revolutionizing",
    "leverage",
    "comprehensive guide",
    "in the ever-evolving",
    "seamlessly",
    "seamless integration",
    "empower",
    "empowering",
    "cutting-edge",
    "state-of-the-art",
    "harness the power",
    "at its core",
    "tapestry",
    "rich tapestry",
]

# Author-specific banned transitions (from ai-detection-rules.md)
AUTHOR_BANNED_TRANSITIONS = [
    "here's what i keep running into",
    "where i've landed:",
    "here's the thing",
    "here's what",  # catches "here's what [noun] aren't hearing:"
]

# 26 AI trigger words (max 5 per 1,000 words)
AI_TRIGGER_WORDS = [
    "delve", "tapestry", "multifaceted", "testament", "pivotal", "robust",
    "cutting-edge", "furthermore", "indeed", "moreover", "utilize", "leverage",
    "comprehensive", "landscape", "crucial", "foster", "illuminate", "underscore",
    "embark", "endeavor", "facilitate", "paramount", "nuanced", "intricate",
    "meticulous", "realm",
]

# Transition words/phrases for readability scoring
TRANSITION_WORDS = [
    "however", "therefore", "furthermore", "moreover", "additionally",
    "consequently", "nevertheless", "meanwhile", "similarly", "likewise",
    "nonetheless", "accordingly", "subsequently", "hence", "thus",
    "in contrast", "on the other hand", "for example", "for instance",
    "in addition", "as a result", "in other words", "that said",
    "in particular", "specifically", "alternatively", "conversely",
    "in fact", "notably", "importantly", "significantly",
]

# Experience signal patterns (from ai-detection-rules.md)
EXPERIENCE_PATTERNS = [
    r'\bwhen I tested\b',
    r'\bin my experience\b',
    r'\bafter implementing\b',
    r'\bover the past \d+\b',
    r"\bhere's what the data shows\b",
    r"\bI've personally\b",
    r'\bI ran this\b',
    r'\bwhat surprised me\b',
    r'\bthe mistake most\b',
    r'\bwhen I worked\b',
    r'\bI found\b',
    r'\bI discovered\b',
    r'\bI tested\b',
    r'\bI built\b',
    r'\bI created\b',
    r'\bI noticed\b',
    r'\bI learned\b',
    r'\bfrom my testing\b',
    r'\bfrom my research\b',
    r'\bfrom my analysis\b',
    r'\bfrom my work\b',
]

# Content type word-count benchmarks
CONTENT_TYPE_BENCHMARKS: dict[str, tuple[int, int]] = {
    'thought-leadership': (800, 1500),
    'how-to-guide': (1500, 3000),
    'builder-narrative': (1500, 3000),
    'operator-review': (1000, 2000),
    'data-research': (1500, 3000),
    'comparison': (1200, 2500),
    'faq-myth-busting': (1200, 2500),
    'news-analysis': (800, 1500),
    'pillar-page': (2500, 5000),
    'operator-curation': (1200, 2500),
    'narrative-tutorial': (1500, 3000),
    'personality-micro': (200, 600),
    'linkedin': (200, 800),
    'default': (800, 2000),
}

# Source tier classification (from seo-aeo-scoring.md)
TIER1_DOMAINS = [
    'google.com/search', 'developers.google.com', '.gov', '.edu',
    'w3.org', 'who.int', 'un.org', 'ieee.org', 'acm.org',
]

TIER2_DOMAINS = [
    'ahrefs.com', 'sparktoro.com', 'seer', 'brightedge.com',
    'princeton.edu', 'semrush.com', 'searchengineland.com',
    'searchenginejournal.com', 'seroundtable.com',
    'theverge.com', 'wired.com', 'techcrunch.com',
]


# ---------------------------------------------------------------------------
# Frontmatter extraction
# ---------------------------------------------------------------------------


def extract_frontmatter(content: str) -> dict[str, Any]:
    """Extract YAML frontmatter from markdown content."""
    frontmatter: dict[str, Any] = {}
    match = re.match(r'^---\s*\n(.*?)\n---\s*\n', content, re.DOTALL)
    if match:
        fm_text = match.group(1)
        for line in fm_text.split('\n'):
            if ':' in line:
                key, _, value = line.partition(':')
                key = key.strip()
                value = value.strip().strip('"').strip("'")
                if value:
                    frontmatter[key] = value
    return frontmatter


def strip_frontmatter(content: str) -> str:
    """Remove YAML frontmatter from content."""
    return re.sub(r'^---\s*\n.*?\n---\s*\n', '', content, count=1, flags=re.DOTALL)


# ---------------------------------------------------------------------------
# Heading analysis
# ---------------------------------------------------------------------------


def analyze_headings(content: str) -> dict[str, Any]:
    """Analyze heading structure and keyword placement."""
    headings: list[dict[str, Any]] = []
    for match in re.finditer(r'^(#{1,6})\s+(.+)$', content, re.MULTILINE):
        level = len(match.group(1))
        text = match.group(2).strip()
        is_question = text.rstrip().endswith('?')
        headings.append({
            'level': level,
            'text': text,
            'is_question': is_question,
            'line': content[:match.start()].count('\n') + 1,
        })

    h1_count = sum(1 for h in headings if h['level'] == 1)
    h2_count = sum(1 for h in headings if h['level'] == 2)
    h3_count = sum(1 for h in headings if h['level'] == 3)
    h2_questions = sum(1 for h in headings if h['level'] == 2 and h['is_question'])
    question_ratio = h2_questions / h2_count if h2_count > 0 else 0

    # Check for hierarchy skips
    hierarchy_clean = True
    prev_level = 0
    for h in headings:
        if h['level'] > prev_level + 1 and prev_level > 0:
            hierarchy_clean = False
        prev_level = h['level']

    return {
        'headings': headings,
        'h1_count': h1_count,
        'h2_count': h2_count,
        'h3_count': h3_count,
        'h2_question_count': h2_questions,
        'h2_question_ratio': round(question_ratio, 2),
        'hierarchy_clean': hierarchy_clean,
        'total': len(headings),
    }


# ---------------------------------------------------------------------------
# Paragraph analysis
# ---------------------------------------------------------------------------


def analyze_paragraphs(content: str) -> dict[str, Any]:
    """Analyze paragraph lengths."""
    cleaned = re.sub(r'```.*?```', '', content, flags=re.DOTALL)
    cleaned = re.sub(r'<[^>]+>', '', cleaned)
    cleaned = re.sub(r'^#{1,6}\s+.*$', '', cleaned, flags=re.MULTILINE)
    cleaned = re.sub(r'!\[.*?\]\(.*?\)', '', cleaned)

    paragraphs = [p.strip() for p in re.split(r'\n\s*\n', cleaned) if p.strip()]

    word_counts: list[int] = []
    over_80 = 0
    over_150 = 0
    over_200 = 0
    in_range = 0  # 40-80 words (ideal)

    for p in paragraphs:
        words = len(p.split())
        if words < 5:
            continue
        word_counts.append(words)
        if words > 200:
            over_200 += 1
        if words > 150:
            over_150 += 1
        if words > 80:
            over_80 += 1
        if 40 <= words <= 80:
            in_range += 1

    total = len(word_counts)
    avg = sum(word_counts) / total if total else 0
    in_range_ratio = in_range / total if total else 0

    return {
        'total_paragraphs': total,
        'avg_word_count': round(avg, 1),
        'over_80_words': over_80,
        'over_150_words': over_150,
        'over_200_words': over_200,
        'in_ideal_range': in_range,
        'in_range_ratio': round(in_range_ratio, 2),
        'max_word_count': max(word_counts) if word_counts else 0,
        'total_word_count': sum(word_counts),
    }


# ---------------------------------------------------------------------------
# Sentence analysis
# ---------------------------------------------------------------------------


def analyze_sentences(text: str) -> dict[str, Any]:
    """Analyze sentence lengths, burstiness (variance), and structure."""
    sentences = re.split(r'(?<=[.!?])\s+', text)
    lengths = [len(s.split()) for s in sentences if len(s.split()) > 2]
    if not lengths:
        return {
            'count': 0,
            'avg_length': 0,
            'max_length': 0,
            'burstiness': 0.0,
            'std_dev': 0.0,
            'over_20_count': 0,
            'over_20_pct': 0.0,
            'over_25_count': 0,
            'very_long_count': 0,
        }

    avg = sum(lengths) / len(lengths)
    std_dev = (sum((l - avg) ** 2 for l in lengths) / len(lengths)) ** 0.5
    burstiness = std_dev / avg if avg > 0 else 0
    very_long = sum(1 for l in lengths if l > 40)
    over_20 = sum(1 for l in lengths if l > 20)
    over_25 = sum(1 for l in lengths if l > 25)
    total = len(lengths)

    return {
        'count': total,
        'avg_length': round(avg, 1),
        'max_length': max(lengths),
        'burstiness': round(burstiness, 2),
        'std_dev': round(std_dev, 1),
        'over_20_count': over_20,
        'over_20_pct': round(over_20 / total * 100, 1) if total else 0,
        'over_25_count': over_25,
        'very_long_count': very_long,
    }


# ---------------------------------------------------------------------------
# Readability analysis (graceful degradation)
# ---------------------------------------------------------------------------


def analyze_readability(text: str) -> dict[str, Any]:
    """Compute readability metrics using textstat if available, else estimate."""
    words = text.split()
    word_count = len(words)
    sentences = re.findall(r'[.!?]+', text)
    sentence_count = len(sentences) if sentences else 1
    avg_sentence_len = word_count / sentence_count

    if HAS_TEXTSTAT:
        fre = textstat.flesch_reading_ease(text)
        fkg = textstat.flesch_kincaid_grade(text)
        fog = textstat.gunning_fog(text)
        try:
            reading_time = round(textstat.reading_time(text, ms_per_char=14.69) / 60, 1)
        except Exception:
            reading_time = round(word_count / 238, 1)
        return {
            'flesch_reading_ease': round(fre, 1),
            'flesch_kincaid_grade': round(fkg, 1),
            'gunning_fog': round(fog, 1),
            'reading_time_minutes': reading_time,
            'avg_sentence_length': round(avg_sentence_len, 1),
            'estimated': False,
        }
    else:
        # Rough Flesch estimate
        avg_word_len = len(text) / max(word_count, 1)
        est_syllable_ratio = avg_word_len / 4.7
        fre = max(0, 206.835 - 1.015 * avg_sentence_len - 84.6 * est_syllable_ratio)
        return {
            'flesch_reading_ease': round(fre, 1),
            'reading_time_minutes': round(word_count / 238, 1),
            'avg_sentence_length': round(avg_sentence_len, 1),
            'estimated': True,
        }


# ---------------------------------------------------------------------------
# Banned phrase detection with line numbers
# ---------------------------------------------------------------------------


def analyze_banned_phrases(content: str, body_lines: list[str]) -> list[dict[str, Any]]:
    """Detect banned AI phrases with count and line locations."""
    found: list[dict[str, Any]] = []
    all_banned = BANNED_PHRASES + AUTHOR_BANNED_TRANSITIONS

    for phrase in all_banned:
        locations: list[str] = []
        count = 0
        for i, line in enumerate(body_lines, 1):
            if phrase in line.lower():
                locations.append(f"line {i}")
                count += 1
        if count > 0:
            found.append({
                'phrase': phrase,
                'count': count,
                'locations': locations,
            })

    return found


# ---------------------------------------------------------------------------
# AI trigger word detection
# ---------------------------------------------------------------------------


def analyze_ai_trigger_words(text: str) -> dict[str, Any]:
    """Count AI trigger words per 1,000 words."""
    words = text.split()
    word_count = len(words)
    if word_count == 0:
        return {'trigger_count': 0, 'per_1k': 0.0, 'found': []}

    lower_text = text.lower()
    found: list[dict[str, Any]] = []
    total = 0
    for tw in AI_TRIGGER_WORDS:
        count = len(re.findall(r'\b' + re.escape(tw) + r'\b', lower_text))
        if count > 0:
            found.append({'word': tw, 'count': count})
            total += count

    per_1k = round(total / word_count * 1000, 1)

    return {
        'trigger_count': total,
        'per_1k': per_1k,
        'found': found,
    }


# ---------------------------------------------------------------------------
# Passive voice estimation
# ---------------------------------------------------------------------------


def analyze_passive_voice(text: str) -> dict[str, Any]:
    """Estimate passive voice percentage using regex heuristics."""
    sentences = re.split(r'(?<=[.!?])\s+', text)
    sentences = [s for s in sentences if len(s.split()) > 2]
    if not sentences:
        return {'passive_count': 0, 'total_sentences': 0, 'passive_pct': 0.0}

    passive_pattern = re.compile(
        r'\b(was|were|been|being|is|are|am|get|got|gets|getting)\s+'
        r'(\w+ly\s+)?'  # optional adverb
        r'(\w+ed|written|spoken|taken|given|made|done|seen|known|shown|built|sent|found|held|told|left|run|set|kept|brought|thought|put)\b',
        re.IGNORECASE,
    )
    passive_count = sum(1 for s in sentences if passive_pattern.search(s))

    return {
        'passive_count': passive_count,
        'total_sentences': len(sentences),
        'passive_pct': round(passive_count / len(sentences) * 100, 1),
    }


# ---------------------------------------------------------------------------
# Transition word analysis
# ---------------------------------------------------------------------------


def analyze_transition_words(text: str) -> dict[str, Any]:
    """Measure percentage of sentences containing transition words."""
    sentences = re.split(r'(?<=[.!?])\s+', text)
    sentences = [s for s in sentences if len(s.split()) > 2]
    if not sentences:
        return {'transition_count': 0, 'total_sentences': 0, 'transition_pct': 0.0}

    lower_sentences = [s.lower() for s in sentences]
    transition_count = 0
    for s in lower_sentences:
        for tw in TRANSITION_WORDS:
            if tw in s:
                transition_count += 1
                break

    return {
        'transition_count': transition_count,
        'total_sentences': len(sentences),
        'transition_pct': round(transition_count / len(sentences) * 100, 1),
    }


# ---------------------------------------------------------------------------
# Citation analysis
# ---------------------------------------------------------------------------


def _classify_source_tier(url: str) -> int:
    """Classify a URL into tier 1, 2, or 3."""
    url_lower = url.lower()
    for domain in TIER1_DOMAINS:
        if domain in url_lower:
            return 1
    for domain in TIER2_DOMAINS:
        if domain in url_lower:
            return 2
    return 3


def analyze_citations(content: str) -> dict[str, Any]:
    """Analyze statistics and their citations with tier classification."""
    stat_patterns = re.findall(r'\d+\.?\d*%', content)

    # Inline citations: ([Source](url), year) or [text](url)
    inline_matches = re.findall(r'\[([^\]]+)\]\((https?://[^)]+)\)', content)
    citations_with_urls = [(text, url) for text, url in inline_matches]

    # Parenthetical citations (Source Name, year)
    paren_citations = re.findall(r'\(([^)]*(?:20\d{2})[^)]*)\)', content)

    # Tier classification
    tier_counts = {1: 0, 2: 0, 3: 0}
    for _, url in citations_with_urls:
        tier = _classify_source_tier(url)
        tier_counts[tier] += 1

    # Sourced vs unsourced stats
    sourced_stats = 0
    unsourced_stats = 0
    for stat in stat_patterns:
        pos = content.find(stat)
        if pos >= 0:
            context = content[pos:pos + 200]
            if re.search(r'\[.+\]\(https?://', context) or re.search(r'\([^)]*20\d{2}[^)]*\)', context):
                sourced_stats += 1
            else:
                unsourced_stats += 1

    return {
        'total_statistics': len(stat_patterns),
        'sourced_statistics': sourced_stats,
        'unsourced_statistics': unsourced_stats,
        'inline_citations': len(citations_with_urls),
        'paren_citations': len(paren_citations),
        'unique_sources': len(set(url.lower() for _, url in citations_with_urls)),
        'tier_counts': tier_counts,
    }


# ---------------------------------------------------------------------------
# Link analysis
# ---------------------------------------------------------------------------


def analyze_links(content: str) -> dict[str, Any]:
    """Analyze internal and external links, and [PRIOR-POST] markers."""
    # [PRIOR-POST] markers
    prior_post_count = len(re.findall(r'\[PRIOR-POST\]', content, re.IGNORECASE))

    # Internal links: relative paths
    internal = re.findall(r'\[([^\]]+)\]\((?!https?://|#)([^)]+)\)', content)
    # External links
    external = re.findall(r'\[([^\]]+)\]\((https?://[^)]+)\)', content)

    bad_anchor_keywords = {'click here', 'read more', 'this article', 'here', 'link', 'this'}
    bad_anchors = [a for a, _ in internal + external if a.lower().strip() in bad_anchor_keywords]

    # Tier classification for external links
    tier_counts = {1: 0, 2: 0, 3: 0}
    for _, url in external:
        tier = _classify_source_tier(url)
        tier_counts[tier] += 1

    return {
        'prior_post_count': prior_post_count,
        'internal_count': len(internal) + prior_post_count,
        'external_count': len(external),
        'total_links': len(internal) + len(external) + prior_post_count,
        'bad_anchor_texts': bad_anchors,
        'external_tier_counts': tier_counts,
    }


# ---------------------------------------------------------------------------
# Originality markers
# ---------------------------------------------------------------------------


def analyze_originality(content: str) -> dict[str, Any]:
    """Detect originality markers and first-person experience signals."""
    marker_counts = {
        'personal_experience': len(re.findall(r'\[PERSONAL EXPERIENCE\]', content, re.IGNORECASE)),
        'original_data': len(re.findall(r'\[ORIGINAL DATA\]', content, re.IGNORECASE)),
        'unique_insight': len(re.findall(r'\[UNIQUE INSIGHT\]', content, re.IGNORECASE)),
        'stat': len(re.findall(r'\[STAT\]', content, re.IGNORECASE)),
        'prior_post': len(re.findall(r'\[PRIOR-POST\]', content, re.IGNORECASE)),
    }

    total_markers = marker_counts['personal_experience'] + marker_counts['original_data'] + marker_counts['unique_insight']

    # First-person experience signals
    first_person_count = 0
    for pattern in EXPERIENCE_PATTERNS:
        first_person_count += len(re.findall(pattern, content, re.IGNORECASE))

    return {
        'marker_counts': marker_counts,
        'total_info_markers': total_markers,
        'first_person_count': first_person_count,
    }


# ---------------------------------------------------------------------------
# Engagement elements
# ---------------------------------------------------------------------------


def analyze_engagement(content: str) -> dict[str, Any]:
    """Detect questions in body text, examples, hooks."""
    body_lines = [l for l in content.split('\n') if not l.strip().startswith('#')]
    body_text = '\n'.join(body_lines)
    questions_in_text = len(re.findall(r'[^#]\?', body_text))

    example_patterns = [
        r'(?i)\bfor example\b', r'(?i)\bfor instance\b', r'(?i)\bsuch as\b',
        r'(?i)\bconsider\b', r'(?i)\blet\'s say\b', r'(?i)\bimagine\b',
        r'(?i)\bhere\'s (?:an|a) example\b',
    ]
    example_count = sum(len(re.findall(p, content)) for p in example_patterns)

    return {
        'questions_in_text': questions_in_text,
        'example_count': example_count,
    }


# ---------------------------------------------------------------------------
# Section analysis (for AEO/GEO scoring)
# ---------------------------------------------------------------------------


def analyze_sections(content: str) -> dict[str, Any]:
    """Analyze sections between headings for citability and answer-first."""
    lines = content.split('\n')
    sections: list[dict[str, Any]] = []
    current_heading = None
    current_lines: list[str] = []

    for line in lines:
        heading_match = re.match(r'^(#{1,6})\s+(.+)$', line)
        if heading_match:
            if current_heading is not None:
                text = '\n'.join(current_lines).strip()
                word_count = len(text.split()) if text else 0
                sections.append({
                    'heading': current_heading,
                    'word_count': word_count,
                    'text': text,
                })
            current_heading = heading_match.group(2).strip()
            current_lines = []
        else:
            current_lines.append(line)

    # Last section
    if current_heading is not None:
        text = '\n'.join(current_lines).strip()
        word_count = len(text.split()) if text else 0
        sections.append({
            'heading': current_heading,
            'word_count': word_count,
            'text': text,
        })

    # Citability: sections 120-180 words
    citable = sum(1 for s in sections if 120 <= s['word_count'] <= 180)
    over_300 = sum(1 for s in sections if s['word_count'] > 300)

    # Answer-first check: first 2 sentences of each section are direct statements
    answer_first_count = 0
    for s in sections:
        if s['text']:
            first_sentences = re.split(r'(?<=[.!?])\s+', s['text'])[:2]
            first_text = ' '.join(first_sentences)
            # Direct statement = not a question, not starting with "However" etc.
            if first_text and not first_text.strip().endswith('?'):
                answer_first_count += 1

    # Citation capsule detection (2-3 sentence summaries after sections)
    capsule_count = 0
    for s in sections:
        if s['text']:
            paragraphs = [p.strip() for p in s['text'].split('\n\n') if p.strip()]
            if paragraphs:
                last_para = paragraphs[-1]
                last_sentences = re.split(r'(?<=[.!?])\s+', last_para)
                last_sentences = [s for s in last_sentences if len(s.split()) > 2]
                if 2 <= len(last_sentences) <= 3:
                    last_word_count = len(last_para.split())
                    if 30 <= last_word_count <= 80:
                        capsule_count += 1

    return {
        'section_count': len(sections),
        'citable_sections': citable,
        'over_300_words': over_300,
        'answer_first_count': answer_first_count,
        'answer_first_ratio': round(answer_first_count / len(sections), 2) if sections else 0,
        'capsule_count': capsule_count,
    }


# ---------------------------------------------------------------------------
# FAQ analysis
# ---------------------------------------------------------------------------


def analyze_faq(content: str) -> dict[str, Any]:
    """Check for FAQ section."""
    has_faq_section = bool(re.search(r'(?i)#{1,3}\s*(?:FAQ|Frequently Asked)', content))
    faq_items = 0
    if has_faq_section:
        faq_match = re.search(r'(?i)#{1,3}\s*(?:FAQ|Frequently Asked).*', content, re.DOTALL)
        if faq_match:
            faq_text = faq_match.group()
            faq_items = len(re.findall(r'^#{3,4}\s+.+\?', faq_text, re.MULTILINE))

    return {
        'has_faq_section': has_faq_section,
        'faq_item_count': faq_items,
    }


# ---------------------------------------------------------------------------
# Content type detection
# ---------------------------------------------------------------------------


def _detect_content_type(frontmatter: dict[str, Any], filename: str = '') -> str:
    """Detect content type from frontmatter or filename."""
    content_type = frontmatter.get('type', frontmatter.get('content_type', '')).lower()
    if content_type and content_type in CONTENT_TYPE_BENCHMARKS:
        return content_type

    # Detect from filename prefix
    basename = Path(filename).name if filename else ''
    if basename.startswith(('LI-', 'li-')) or '-LI-' in basename:
        return 'linkedin'

    # Detect from frontmatter fields
    title = frontmatter.get('title', '').lower()
    if 'guide' in title:
        return 'how-to-guide'
    if 'how to' in title:
        return 'how-to-guide'
    if 'review' in title:
        return 'operator-review'
    if 'comparison' in title or 'vs' in title:
        return 'comparison'

    return 'default'


# ---------------------------------------------------------------------------
# Scoring: 5-category, 100-point system
# ---------------------------------------------------------------------------


def calculate_score(analysis: dict[str, Any]) -> dict[str, Any]:
    """Calculate the 5-category, 100-point quality score."""
    issues: list[dict[str, Any]] = []

    # ===================================================================
    # 1. CONTENT QUALITY (30 pts)
    # ===================================================================
    cq = 0
    cq_breakdown: dict[str, Any] = {}

    # Depth / comprehensiveness: 7 pts
    paras = analysis['paragraphs']
    word_count = paras['total_word_count']
    content_type = analysis.get('_content_type', 'default')
    bench_min, bench_max = CONTENT_TYPE_BENCHMARKS.get(content_type, (800, 2000))

    if bench_min <= word_count <= bench_max:
        depth_score = 7
    elif word_count >= bench_min * 0.7:
        depth_score = 5
    elif word_count >= bench_min * 0.5:
        depth_score = 3
    else:
        depth_score = 1
        issues.append({'category': 'content_quality', 'severity': 'high',
                       'issue': f'Word count ({word_count}) below benchmark ({bench_min}-{bench_max}) for {content_type}'})
    if word_count > bench_max * 1.5:
        depth_score = max(depth_score - 2, 1)
        issues.append({'category': 'content_quality', 'severity': 'medium',
                       'issue': f'Word count ({word_count}) excessively long for {content_type}'})
    cq += depth_score
    cq_breakdown['depth'] = depth_score

    # Readability (Flesch 60-70 ideal): 7 pts
    readability = analysis['readability']
    fre = readability.get('flesch_reading_ease', 50)
    if 60 <= fre <= 70:
        read_score = 7
    elif 55 <= fre <= 75:
        read_score = 5
    elif 45 <= fre <= 80:
        read_score = 3
    else:
        read_score = 1
        issues.append({'category': 'content_quality', 'severity': 'high',
                       'issue': f'Flesch reading ease ({fre}) outside acceptable range (55-75)'})
    cq += read_score
    cq_breakdown['readability'] = read_score

    # Originality markers: 5 pts (3+ markers = full points)
    orig = analysis['originality']
    total_markers = orig['total_info_markers']
    if total_markers >= 3:
        orig_score = 5
    elif total_markers == 2:
        orig_score = 4
    elif total_markers == 1:
        orig_score = 2
    elif orig['first_person_count'] >= 3:
        orig_score = 3
    elif orig['first_person_count'] >= 1:
        orig_score = 1
    else:
        orig_score = 0
        issues.append({'category': 'content_quality', 'severity': 'medium',
                       'issue': 'No originality markers found -- add [PERSONAL EXPERIENCE], [ORIGINAL DATA], or [UNIQUE INSIGHT]'})
    cq += orig_score
    cq_breakdown['originality'] = orig_score

    # Sentence/paragraph structure: 4 pts
    sentences = analysis['sentences']
    struct_score = 0
    # avg sentence 15-20 words
    if sentences['count'] > 0:
        if 15 <= sentences['avg_length'] <= 20:
            struct_score += 2
        elif 12 <= sentences['avg_length'] <= 25:
            struct_score += 1
        else:
            issues.append({'category': 'content_quality', 'severity': 'medium',
                           'issue': f'Average sentence length ({sentences["avg_length"]}) outside ideal range (15-20 words)'})
    # <=25% over 20 words
    if sentences['over_20_pct'] <= 25:
        struct_score += 1
    else:
        issues.append({'category': 'content_quality', 'severity': 'medium',
                       'issue': f'{sentences["over_20_pct"]}% of sentences over 20 words (target: <=25%)'})
    # Paragraph structure (40-80 words)
    if paras['over_200_words'] == 0 and paras['total_paragraphs'] > 0:
        struct_score += 1
    elif paras['over_200_words'] > 0:
        issues.append({'category': 'content_quality', 'severity': 'critical',
                       'issue': f'{paras["over_200_words"]} paragraphs over 200 words'})
    struct_score = min(struct_score, 4)
    cq += struct_score
    cq_breakdown['structure'] = struct_score

    # Engagement elements: 4 pts
    engagement = analysis['engagement']
    eng_score = 0
    if engagement['questions_in_text'] >= 2:
        eng_score += 2
    elif engagement['questions_in_text'] >= 1:
        eng_score += 1
    if engagement['example_count'] >= 2:
        eng_score += 2
    elif engagement['example_count'] >= 1:
        eng_score += 1
    eng_score = min(eng_score, 4)
    if eng_score < 2:
        issues.append({'category': 'content_quality', 'severity': 'low',
                       'issue': 'Low engagement -- add questions and examples in body text'})
    cq += eng_score
    cq_breakdown['engagement'] = eng_score

    # Grammar/anti-pattern: 3 pts
    passive = analysis.get('passive_voice', {})
    transitions = analysis.get('transition_words', {})
    ai_triggers = analysis.get('ai_trigger_words', {})
    gram_score = 0
    passive_pct = passive.get('passive_pct', 0)
    # 1 pt: passive voice <=10%
    if passive_pct <= 10:
        gram_score += 1
    elif passive_pct > 15:
        issues.append({'category': 'content_quality', 'severity': 'high',
                       'issue': f'Passive voice at {passive_pct}% -- target <=10%, max 15%'})
    # 1 pt: AI trigger words <=5/1K
    trigger_per_1k = ai_triggers.get('per_1k', 0)
    if trigger_per_1k <= 5:
        gram_score += 1
    elif trigger_per_1k > 8:
        issues.append({'category': 'content_quality', 'severity': 'high',
                       'issue': f'AI trigger words: {trigger_per_1k}/1K -- target <=5, max 8'})
    else:
        issues.append({'category': 'content_quality', 'severity': 'medium',
                       'issue': f'AI trigger words: {trigger_per_1k}/1K -- target <=5'})
    # 1 pt: transition words 20-30%
    transition_pct = transitions.get('transition_pct', 0)
    if 20 <= transition_pct <= 30:
        gram_score += 1
    elif transition_pct < 15:
        issues.append({'category': 'content_quality', 'severity': 'medium',
                       'issue': f'Transition words at {transition_pct}% -- target 20-30%'})
    elif transition_pct > 35:
        issues.append({'category': 'content_quality', 'severity': 'medium',
                       'issue': f'Transition words at {transition_pct}% -- reads formulaic, target 20-30%'})
    gram_score = min(gram_score, 3)
    cq += gram_score
    cq_breakdown['grammar_antipattern'] = gram_score

    cq = min(cq, 30)

    # ===================================================================
    # 2. SEO OPTIMIZATION (20 pts)
    # ===================================================================
    seo = 0
    seo_breakdown: dict[str, Any] = {}
    fm = analysis['frontmatter']

    # Heading hierarchy with keywords: 5 pts
    headings = analysis['headings']
    heading_score = 0
    if headings['h1_count'] == 1:
        heading_score += 1
    elif headings['h1_count'] == 0 and fm.get('title'):
        heading_score += 1  # Title serves as H1
    if headings['h2_count'] >= 3:
        heading_score += 2
    elif headings['h2_count'] >= 1:
        heading_score += 1
    else:
        issues.append({'category': 'seo_optimization', 'severity': 'high',
                       'issue': 'No H2 headings -- add section headings for structure'})
    if headings['hierarchy_clean']:
        heading_score += 1
    else:
        issues.append({'category': 'seo_optimization', 'severity': 'critical',
                       'issue': 'Heading hierarchy has skips (e.g., H2 to H4)'})
    if headings['h3_count'] >= 1:
        heading_score += 1
    heading_score = min(heading_score, 5)
    seo += heading_score
    seo_breakdown['headings'] = heading_score

    # Title optimization: 4 pts (Substack: <=60 chars)
    title = fm.get('title', '')
    title_len = len(title)
    title_score = 0
    if title_len > 0 and title_len <= 60:
        title_score = 4
    elif title_len > 0 and title_len <= 70:
        title_score = 2
    elif title:
        title_score = 1
        issues.append({'category': 'seo_optimization', 'severity': 'high',
                       'issue': f'Title length ({title_len} chars) exceeds 60-char Substack limit'})
    else:
        issues.append({'category': 'seo_optimization', 'severity': 'high',
                       'issue': 'Missing title in frontmatter'})
    seo += title_score
    seo_breakdown['title'] = title_score

    # Keyword placement: 4 pts
    keyword = fm.get('keyword', fm.get('keywords', '')).split(',')[0].strip().lower() if fm.get('keyword', fm.get('keywords', '')) else ''
    keyword_score = 0
    if keyword:
        body = analysis.get('_body_text', '')
        # Present in first 100 words
        first_100 = ' '.join(body.split()[:100]).lower()
        if keyword in first_100:
            keyword_score += 2
        # Present in headings
        h_texts = ' '.join(h['text'].lower() for h in headings['headings'])
        if keyword in h_texts:
            keyword_score += 1
        # Present in title
        if keyword in title.lower():
            keyword_score += 1
    else:
        keyword_score = 2  # No keyword defined; give partial credit
    keyword_score = min(keyword_score, 4)
    seo += keyword_score
    seo_breakdown['keyword_placement'] = keyword_score

    # Internal/cross-linking: 4 pts (3-10 via [PRIOR-POST] or relative links)
    links = analysis['links']
    int_count = links['internal_count']
    int_score = 0
    if 3 <= int_count <= 10:
        int_score = 4
    elif int_count >= 1:
        int_score = 2
    else:
        issues.append({'category': 'seo_optimization', 'severity': 'medium',
                       'issue': 'No internal links -- add 3-10 contextual links via [PRIOR-POST] markers'})
    if links['bad_anchor_texts']:
        int_score = max(int_score - 1, 0)
        issues.append({'category': 'seo_optimization', 'severity': 'low',
                       'issue': f'Bad anchor texts found: {links["bad_anchor_texts"]}'})
    seo += int_score
    seo_breakdown['internal_linking'] = int_score

    # Meta/subtitle: 3 pts (Substack subtitle 150-160 chars)
    subtitle = fm.get('subtitle', fm.get('description', ''))
    sub_len = len(subtitle)
    meta_score = 0
    if 150 <= sub_len <= 160:
        meta_score = 3
    elif 120 <= sub_len <= 170:
        meta_score = 2
    elif subtitle:
        meta_score = 1
    else:
        issues.append({'category': 'seo_optimization', 'severity': 'medium',
                       'issue': 'Missing subtitle/meta description in frontmatter'})
    seo += meta_score
    seo_breakdown['meta_subtitle'] = meta_score

    seo = min(seo, 20)

    # ===================================================================
    # 3. E-E-A-T SIGNALS (15 pts)
    # ===================================================================
    eeat = 0
    eeat_breakdown: dict[str, Any] = {}

    # Author attribution: 4 pts
    author = fm.get('author', fm.get('authors', ''))
    author_score = 0
    if author and author.lower() not in ('admin', 'administrator', 'staff', 'team', ''):
        author_score = 4
    elif author:
        author_score = 1
        issues.append({'category': 'eeat_signals', 'severity': 'critical',
                       'issue': f'Generic author name "{author}" -- use a real person name'})
    else:
        issues.append({'category': 'eeat_signals', 'severity': 'critical',
                       'issue': 'No author attribution in frontmatter'})
    eeat += author_score
    eeat_breakdown['author'] = author_score

    # Source citations: 4 pts (minimum 6 sourced statistics)
    cit = analysis['citations']
    cit_score = 0
    total_citations = cit['inline_citations'] + cit['paren_citations']
    sourced = cit['sourced_statistics']
    if sourced >= 6:
        cit_score = 4
    elif sourced >= 4:
        cit_score = 3
    elif sourced >= 2:
        cit_score = 2
    elif total_citations >= 1:
        cit_score = 1
    else:
        issues.append({'category': 'eeat_signals', 'severity': 'high',
                       'issue': 'No source citations -- add inline citations to credible sources (minimum 6)'})
    cit_score = min(cit_score, 4)
    eeat += cit_score
    eeat_breakdown['citations'] = cit_score

    # Trust indicators: 4 pts
    trust_score = 0
    body = analysis.get('_body_text', '')
    # Consistent formatting (has headings and structured sections)
    if headings['h2_count'] >= 2:
        trust_score += 2
    elif headings['h2_count'] >= 1:
        trust_score += 1
    # Editorial notes or consistent quality signals
    if re.search(r'(?i)\b(?:editorial|editor.?s? note|reviewed by|fact.?check)\b', body):
        trust_score += 1
    # Consistent formatting (paragraphs in range)
    if paras['in_range_ratio'] >= 0.5:
        trust_score += 1
    trust_score = min(trust_score, 4)
    eeat += trust_score
    eeat_breakdown['trust'] = trust_score

    # Experience signals: 3 pts (minimum 3 first-person markers)
    exp_score = 0
    if orig['first_person_count'] >= 3:
        exp_score = 3
    elif orig['first_person_count'] >= 2:
        exp_score = 2
    elif orig['first_person_count'] >= 1:
        exp_score = 1
    if exp_score < 2:
        issues.append({'category': 'eeat_signals', 'severity': 'medium',
                       'issue': f'Only {orig["first_person_count"]} experience signals -- minimum 3 recommended ("When I tested...", "In my experience...")'})
    eeat += exp_score
    eeat_breakdown['experience'] = exp_score

    eeat = min(eeat, 15)

    # ===================================================================
    # 4. AEO/GEO READINESS (20 pts)
    # ===================================================================
    aeo = 0
    aeo_breakdown: dict[str, Any] = {}
    sections = analysis['sections']

    # Answer-first formatting: 5 pts
    af_ratio = sections['answer_first_ratio']
    if af_ratio >= 0.8:
        af_score = 5
    elif af_ratio >= 0.6:
        af_score = 3
    elif af_ratio >= 0.4:
        af_score = 2
    else:
        af_score = 0
        issues.append({'category': 'aeo_geo_readiness', 'severity': 'high',
                       'issue': f'Answer-first ratio {af_ratio} -- most sections should start with a direct statement'})
    aeo += af_score
    aeo_breakdown['answer_first'] = af_score

    # Passage-level citability: 5 pts (120-180 word sections)
    citable = sections['citable_sections']
    if citable >= 5:
        cite_score = 5
    elif citable >= 3:
        cite_score = 3
    elif citable >= 1:
        cite_score = 2
    else:
        cite_score = 0
        issues.append({'category': 'aeo_geo_readiness', 'severity': 'medium',
                       'issue': 'No sections in the 120-180 word sweet spot for AI citations'})
    if sections['over_300_words'] > 0:
        issues.append({'category': 'aeo_geo_readiness', 'severity': 'medium',
                       'issue': f'{sections["over_300_words"]} sections over 300 words -- break up for citability'})
    aeo += cite_score
    aeo_breakdown['citability'] = cite_score

    # Citation capsules: 4 pts
    capsules = sections['capsule_count']
    if capsules >= 3:
        cap_score = 4
    elif capsules >= 2:
        cap_score = 3
    elif capsules >= 1:
        cap_score = 2
    else:
        cap_score = 0
        issues.append({'category': 'aeo_geo_readiness', 'severity': 'medium',
                       'issue': 'No citation capsules detected -- add 2-3 sentence summaries after H2 sections'})
    aeo += cap_score
    aeo_breakdown['citation_capsules'] = cap_score

    # Entity clarity: 3 pts
    # Check for consistent terminology (bold defined terms)
    entity_definitions = len(re.findall(r'\*\*[^*]+\*\*\s*(?:is|are|refers to|means)', body))
    if entity_definitions >= 3:
        ent_score = 3
    elif entity_definitions >= 1:
        ent_score = 2
    else:
        ent_score = 1  # Partial credit for consistent content
        if entity_definitions == 0:
            issues.append({'category': 'aeo_geo_readiness', 'severity': 'low',
                           'issue': 'No entity definitions found -- use **term** is/are patterns'})
    ent_score = min(ent_score, 3)
    aeo += ent_score
    aeo_breakdown['entity_clarity'] = ent_score

    # FAQ/Q&A formatting: 3 pts (target 60-70% H2s as questions)
    faq_info = analysis['faq']
    qa_score = 0
    q_ratio = headings['h2_question_ratio']
    if faq_info['has_faq_section']:
        qa_score += 2
    if 0.6 <= q_ratio <= 0.7:
        qa_score += 1
    elif q_ratio >= 0.4:
        qa_score += 1
    elif headings['h2_question_count'] >= 1:
        qa_score += 1
    qa_score = min(qa_score, 3)
    if not faq_info['has_faq_section'] and content_type not in ('linkedin', 'personality-micro'):
        issues.append({'category': 'aeo_geo_readiness', 'severity': 'high',
                       'issue': 'No FAQ section -- add FAQ for AEO/GEO readiness (Substack)'})
    aeo += qa_score
    aeo_breakdown['faq_qa'] = qa_score

    aeo = min(aeo, 20)

    # ===================================================================
    # 5. ANTI-AI DETECTION (15 pts)
    # ===================================================================
    anti_ai = 0
    anti_ai_breakdown: dict[str, Any] = {}

    # Burstiness: 4 pts
    burstiness = sentences.get('burstiness', 0)
    if burstiness > 0.5:
        burst_score = 4
    elif burstiness >= 0.3:
        burst_score = 2
        issues.append({'category': 'anti_ai_detection', 'severity': 'medium',
                       'issue': f'Burstiness {burstiness} is borderline (0.3-0.5) -- vary sentence lengths more'})
    else:
        burst_score = 0
        issues.append({'category': 'anti_ai_detection', 'severity': 'critical',
                       'issue': f'Burstiness {burstiness} indicates AI-like sentence cadence (< 0.3) -- rewrite for variation'})
    anti_ai += burst_score
    anti_ai_breakdown['burstiness'] = burst_score

    # Banned phrase check: 4 pts (-2 per phrase, min 0)
    banned = analysis['banned_phrases']
    total_banned = sum(b['count'] for b in banned)
    banned_score = max(4 - total_banned * 2, 0)
    if total_banned > 0:
        phrase_list = ', '.join(f"'{b['phrase']}'" for b in banned)
        issues.append({'category': 'anti_ai_detection', 'severity': 'critical',
                       'issue': f'Banned phrase(s) found: {phrase_list}'})
        for b in banned:
            for loc in b['locations']:
                issues.append({'category': 'anti_ai_detection', 'severity': 'critical',
                               'issue': f"Banned phrase '{b['phrase']}' at {loc}"})
    anti_ai += banned_score
    anti_ai_breakdown['banned_phrases'] = banned_score

    # Vocabulary diversity (TTR): 3 pts
    words = analysis.get('_plain_text', '').lower().split()
    unique_words = len(set(words)) if words else 0
    total_words = len(words) if words else 1
    ttr = unique_words / total_words
    if ttr > 0.6:
        ttr_score = 3
    elif ttr >= 0.4:
        ttr_score = 2
    else:
        ttr_score = 0
        issues.append({'category': 'anti_ai_detection', 'severity': 'medium',
                       'issue': f'TTR {round(ttr, 3)} indicates low vocabulary diversity (< 0.4)'})
    anti_ai += ttr_score
    anti_ai_breakdown['vocabulary_diversity'] = ttr_score

    # Passive voice ratio: 2 pts
    if passive_pct <= 10:
        pv_score = 2
    elif passive_pct <= 15:
        pv_score = 1
    else:
        pv_score = 0
    anti_ai += pv_score
    anti_ai_breakdown['passive_voice'] = pv_score

    # AI trigger word density: 2 pts
    if trigger_per_1k <= 5:
        trig_score = 2
    elif trigger_per_1k <= 8:
        trig_score = 1
    else:
        trig_score = 0
    anti_ai += trig_score
    anti_ai_breakdown['trigger_density'] = trig_score

    anti_ai = min(anti_ai, 15)

    # ===================================================================
    # TOTAL
    # ===================================================================
    total = cq + seo + eeat + aeo + anti_ai

    if total >= 90:
        rating = 'Exceptional'
    elif total >= 80:
        rating = 'Strong'
    elif total >= 70:
        rating = 'Acceptable'
    elif total >= 60:
        rating = 'Below Standard'
    else:
        rating = 'Rewrite'

    # Sort issues by severity
    severity_order = {'critical': 0, 'high': 1, 'medium': 2, 'low': 3}
    issues.sort(key=lambda x: severity_order.get(x.get('severity', 'low'), 4))

    return {
        'total': total,
        'rating': rating,
        'categories': {
            'content_quality': {'score': cq, 'max': 30, 'breakdown': cq_breakdown},
            'seo_optimization': {'score': seo, 'max': 20, 'breakdown': seo_breakdown},
            'eeat_signals': {'score': eeat, 'max': 15, 'breakdown': eeat_breakdown},
            'aeo_geo_readiness': {'score': aeo, 'max': 20, 'breakdown': aeo_breakdown},
            'anti_ai_detection': {'score': anti_ai, 'max': 15, 'breakdown': anti_ai_breakdown},
        },
        'issues': issues,
    }


# ---------------------------------------------------------------------------
# File analysis orchestrator
# ---------------------------------------------------------------------------


def analyze_file(file_path: str) -> dict[str, Any]:
    """Analyze a single content file with all analyzers."""
    path = Path(file_path)
    if not path.exists():
        return {'error': f'File not found: {file_path}'}

    content = path.read_text(encoding='utf-8')
    frontmatter = extract_frontmatter(content)
    body = strip_frontmatter(content)

    # Lines for line-number tracking (includes frontmatter)
    all_lines = content.split('\n')

    # Strip markdown formatting for plain-text analysis
    plain_text = re.sub(r'```.*?```', '', body, flags=re.DOTALL)
    plain_text = re.sub(r'<[^>]+>', '', plain_text)
    plain_text = re.sub(r'!\[.*?\]\(.*?\)', '', plain_text)
    plain_text = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', plain_text)
    plain_text = re.sub(r'^#{1,6}\s+', '', plain_text, flags=re.MULTILINE)
    plain_text = re.sub(r'\n{3,}', '\n\n', plain_text).strip()

    content_type = _detect_content_type(frontmatter, str(path))
    headings_info = analyze_headings(body)
    sentences_info = analyze_sentences(plain_text)
    faq_info = analyze_faq(body)
    paras_info = analyze_paragraphs(body)
    originality_info = analyze_originality(body)

    analysis: dict[str, Any] = {
        'file': str(path),
        'frontmatter': frontmatter,
        'headings': headings_info,
        'paragraphs': paras_info,
        'citations': analyze_citations(body),
        'faq': faq_info,
        'readability': analyze_readability(plain_text),
        'sentences': sentences_info,
        'passive_voice': analyze_passive_voice(plain_text),
        'transition_words': analyze_transition_words(plain_text),
        'ai_trigger_words': analyze_ai_trigger_words(plain_text),
        'links': analyze_links(body),
        'originality': originality_info,
        'engagement': analyze_engagement(body),
        'sections': analyze_sections(body),
        'banned_phrases': analyze_banned_phrases(content, all_lines),
        # Internal refs used by scoring
        '_body_text': body,
        '_plain_text': plain_text,
        '_content_type': content_type,
    }

    analysis['score'] = calculate_score(analysis)

    # Compute TTR for metrics output
    words_lower = plain_text.lower().split()
    unique_count = len(set(words_lower)) if words_lower else 0
    total_word_count = len(words_lower) if words_lower else 1
    ttr = round(unique_count / total_word_count, 3)

    # Build output format matching the spec
    result: dict[str, Any] = {
        'file': str(path),
        'frontmatter': frontmatter,
        'score': analysis['score'],
        'metrics': {
            'word_count': paras_info['total_word_count'],
            'sentence_count': sentences_info['count'],
            'burstiness': sentences_info['burstiness'],
            'ttr': ttr,
            'flesch_reading_ease': analysis['readability'].get('flesch_reading_ease', 0),
            'flesch_estimated': analysis['readability'].get('estimated', True),
            'passive_voice_pct': analysis['passive_voice']['passive_pct'],
            'ai_trigger_density': analysis['ai_trigger_words']['per_1k'],
            'avg_sentence_length': sentences_info['avg_length'],
            'marker_counts': originality_info['marker_counts'],
            'content_type': content_type,
        },
        'banned_phrases': analysis['banned_phrases'],
        'ai_trigger_words': analysis['ai_trigger_words']['found'],
    }

    return result


# ---------------------------------------------------------------------------
# Output formatters
# ---------------------------------------------------------------------------


def _format_markdown(result: dict[str, Any]) -> str:
    """Format analysis result as a human-readable markdown report."""
    if 'error' in result:
        return f"## Error\n\n{result['error']}"

    score = result['score']
    lines: list[str] = []
    filename = Path(result['file']).name

    lines.append(f"## Content Quality Report: {filename}")
    lines.append('')
    lines.append(f"### Overall Score: {score['total']}/100 -- {score['rating']}")
    lines.append('')

    # Category table
    lines.append('| Category | Score | Max |')
    lines.append('|----------|------:|----:|')
    cat_names = {
        'content_quality': 'Content Quality',
        'seo_optimization': 'SEO Optimization',
        'eeat_signals': 'E-E-A-T Signals',
        'aeo_geo_readiness': 'AEO/GEO Readiness',
        'anti_ai_detection': 'Anti-AI Detection',
    }
    for key, label in cat_names.items():
        cat = score['categories'].get(key, {})
        s = cat.get('score', 0) if isinstance(cat, dict) else 0
        m = cat.get('max', 0) if isinstance(cat, dict) else 0
        lines.append(f'| {label} | {s} | {m} |')
    lines.append('')

    # Metrics
    metrics = result.get('metrics', {})
    lines.append('### Key Metrics')
    lines.append(f'- Word count: {metrics.get("word_count", "N/A")}')
    lines.append(f'- Content type: {metrics.get("content_type", "default")}')
    lines.append(f'- Burstiness: {metrics.get("burstiness", "N/A")}')
    lines.append(f'- TTR: {metrics.get("ttr", "N/A")}')
    lines.append(f'- Flesch Reading Ease: {metrics.get("flesch_reading_ease", "N/A")}')
    if metrics.get('flesch_estimated'):
        lines.append('  *(Estimated -- install textstat for accurate metrics)*')
    lines.append(f'- Passive voice: {metrics.get("passive_voice_pct", "N/A")}%')
    lines.append(f'- AI trigger density: {metrics.get("ai_trigger_density", "N/A")}/1K')
    lines.append(f'- Avg sentence length: {metrics.get("avg_sentence_length", "N/A")} words')
    lines.append('')

    # Marker counts
    markers = metrics.get('marker_counts', {})
    if any(markers.values()):
        lines.append('### Markers')
        for k, v in markers.items():
            if v > 0:
                lines.append(f'- [{k.upper().replace("_", " ")}]: {v}')
        lines.append('')

    # Banned phrases
    banned = result.get('banned_phrases', [])
    if banned:
        lines.append('### Banned Phrases Found')
        for b in banned:
            lines.append(f'- "{b["phrase"]}" x{b["count"]} at {", ".join(b["locations"])}')
        lines.append('')

    # AI trigger words
    triggers = result.get('ai_trigger_words', [])
    if triggers:
        lines.append('### AI Trigger Words')
        trigger_list = ', '.join(f'{t["word"]}({t["count"]})' for t in triggers[:10])
        lines.append(f'- Found: {trigger_list}')
        lines.append('')

    # Issues
    issues = score.get('issues', [])
    if issues:
        lines.append('### Issues')
        for issue in issues:
            sev = issue.get('severity', 'low').upper()
            lines.append(f'- [{sev}] {issue["issue"]}')
        lines.append('')
    else:
        lines.append('### Issues')
        lines.append('No issues detected.')
        lines.append('')

    return '\n'.join(lines)


def _format_table(result: dict[str, Any]) -> str:
    """Format analysis result as a compact table."""
    if 'error' in result:
        return f"ERROR: {result['error']}"

    score = result['score']
    filename = Path(result['file']).name
    cats = score['categories']

    lines: list[str] = []
    lines.append(f'{filename}  [{score["total"]}/100 {score["rating"]}]')

    cat_parts = []
    for key, label in [('content_quality', 'Content'), ('seo_optimization', 'SEO'),
                       ('eeat_signals', 'E-E-A-T'), ('aeo_geo_readiness', 'AEO/GEO'),
                       ('anti_ai_detection', 'Anti-AI')]:
        cat = cats.get(key, {})
        s = cat.get('score', 0) if isinstance(cat, dict) else 0
        m = cat.get('max', 0) if isinstance(cat, dict) else 0
        cat_parts.append(f'{label}: {s}/{m}')
    lines.append(f'  {" | ".join(cat_parts)}')

    issues = score.get('issues', [])
    critical_issues = [i for i in issues if i.get('severity') in ('critical', 'high')]
    if critical_issues:
        lines.append(f'  ISSUES: {"; ".join(i["issue"] for i in critical_issues[:3])}')

    return '\n'.join(lines)


def _format_fix(result: dict[str, Any]) -> str:
    """Output specific, actionable fixes prioritized by impact."""
    if 'error' in result:
        return f"ERROR: {result['error']}"

    score = result['score']
    issues = score.get('issues', [])
    filename = Path(result['file']).name

    lines: list[str] = []
    lines.append(f"Fixes for {filename} (Score: {score['total']}/100 -- {score['rating']})")
    lines.append('=' * 60)

    if not issues:
        lines.append('No issues found -- content meets all quality checks.')
        return '\n'.join(lines)

    for i, issue in enumerate(issues, 1):
        sev = issue.get('severity', 'low').upper()
        cat = issue.get('category', '').replace('_', ' ').title()
        lines.append(f'{i}. [{sev}] ({cat}) {issue["issue"]}')

    return '\n'.join(lines)


# ---------------------------------------------------------------------------
# Batch processing
# ---------------------------------------------------------------------------


def _process_batch(directory: Path, sort_key: str = 'score') -> dict[str, Any]:
    """Analyze all markdown files in a directory."""
    results: list[dict[str, Any]] = []
    for f in sorted(directory.glob('*.md')):
        results.append(analyze_file(str(f)))

    # Sort
    if sort_key == 'score':
        results.sort(key=lambda r: r.get('score', {}).get('total', 0), reverse=True)
    elif sort_key == 'name':
        results.sort(key=lambda r: r.get('file', ''))
    elif sort_key == 'words':
        results.sort(key=lambda r: r.get('metrics', {}).get('word_count', 0), reverse=True)

    return {'batch': True, 'count': len(results), 'results': results}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main(args: argparse.Namespace) -> None:
    """Main execution function."""
    path = Path(args.input)
    fmt = getattr(args, 'format', 'json')
    fix_mode = getattr(args, 'fix', False)
    sort_key = getattr(args, 'sort', 'score')

    # Batch mode
    if path.is_dir() and getattr(args, 'batch', False):
        batch_result = _process_batch(path, sort_key)

        if fmt == 'markdown':
            for r in batch_result['results']:
                print(_format_markdown(r))
                print('---\n')
        elif fmt == 'table':
            for r in batch_result['results']:
                print(_format_table(r))
            print(f'\nTotal: {batch_result["count"]} files')
        else:
            output = json.dumps(batch_result, indent=2)
            print(output)
        return

    # Single file mode
    if not path.is_file():
        error = {'error': f'Path not found or not a file: {args.input}'}
        if fmt == 'json':
            print(json.dumps(error, indent=2))
        else:
            print(f"ERROR: {error['error']}")
        sys.exit(1)

    result = analyze_file(str(path))

    # Fix mode
    if fix_mode:
        print(_format_fix(result))
        return

    # Format output
    if fmt == 'markdown':
        print(_format_markdown(result))
    elif fmt == 'table':
        print(_format_table(result))
    else:
        print(json.dumps(result, indent=2))


if __name__ == '__main__':
    _print_dependency_notice()

    parser = argparse.ArgumentParser(
        description='Content Quality Analyzer -- 5-category, 100-point scoring system',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python analyze_content.py post.md                          Default JSON output
  python analyze_content.py post.md --format markdown        Markdown report
  python analyze_content.py post.md --format table           Compact table
  python analyze_content.py --batch ./content/ --sort score  Batch analysis
  python analyze_content.py post.md --fix                    Prioritized fix list

Scoring Categories (100 points):
  Content Quality        30 pts   Depth, readability, originality, structure
  SEO Optimization       20 pts   Headings, title, keywords, linking, meta
  E-E-A-T Signals        15 pts   Author, citations, trust, experience
  AEO/GEO Readiness      20 pts   Answer-first, citability, capsules, FAQ
  Anti-AI Detection       15 pts   Burstiness, banned phrases, TTR, passive

Rating Bands:
  90-100  Exceptional    80-89  Strong    70-79  Acceptable
  60-69   Below Standard   <60  Rewrite

Optional dependency (graceful degradation):
  pip install textstat
        """,
    )
    parser.add_argument('input', help='Content file path or directory (with --batch)')
    parser.add_argument('--format', '-f', choices=['json', 'markdown', 'table'],
                        default='json', help='Output format (default: json)')
    parser.add_argument('--batch', action='store_true',
                        help='Analyze all .md files in directory')
    parser.add_argument('--sort', choices=['score', 'name', 'words'],
                        default='score', help='Sort order for batch mode (default: score)')
    parser.add_argument('--fix', action='store_true',
                        help='Output prioritized list of specific fixes')

    args = parser.parse_args()

    try:
        main(args)
    except Exception as e:
        print(json.dumps({'error': str(e)}), file=sys.stderr)
        sys.exit(1)
