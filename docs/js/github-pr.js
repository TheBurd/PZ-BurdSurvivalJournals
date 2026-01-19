/**
 * GitHub Pull Request Creation
 * Handles forking, branching, committing, and PR creation
 */

import { REPO_CONFIG, CATEGORIES } from './config.js';
import { getGitHubToken, isGitHubAuthenticated, getGitHubUser } from './github-auth.js';
import { generateCategoryFile } from './export-utils.js';
import { getEnglishBaseline } from './translation-manager.js';
import { categorizeTranslations } from './lua-parser.js';

const GITHUB_API = 'https://api.github.com';

/**
 * Make authenticated GitHub API request
 * @param {string} endpoint - API endpoint (relative to base)
 * @param {Object} options - Fetch options
 * @returns {Promise<Object>} Response data
 */
async function githubRequest(endpoint, options = {}) {
    const token = getGitHubToken();
    if (!token) {
        throw new Error('Not authenticated with GitHub');
    }

    const url = endpoint.startsWith('http') ? endpoint : `${GITHUB_API}${endpoint}`;

    const response = await fetch(url, {
        ...options,
        headers: {
            'Authorization': `Bearer ${token}`,
            'Accept': 'application/vnd.github.v3+json',
            'Content-Type': 'application/json',
            ...options.headers
        }
    });

    if (!response.ok) {
        const error = await response.json().catch(() => ({}));
        throw new Error(error.message || `GitHub API error: ${response.status}`);
    }

    // Handle empty responses
    const text = await response.text();
    return text ? JSON.parse(text) : {};
}

/**
 * Check if user has a fork of the repo
 * @param {string} username - GitHub username
 * @returns {Promise<Object|null>} Fork info or null
 */
export async function getUserFork(username) {
    try {
        const repo = await githubRequest(`/repos/${username}/${REPO_CONFIG.repo}`);
        if (repo.fork && repo.parent?.full_name === `${REPO_CONFIG.owner}/${REPO_CONFIG.repo}`) {
            return repo;
        }
    } catch (e) {
        // Fork doesn't exist
    }
    return null;
}

/**
 * Create a fork of the main repo
 * @returns {Promise<Object>} Fork info
 */
export async function createFork() {
    const fork = await githubRequest(`/repos/${REPO_CONFIG.owner}/${REPO_CONFIG.repo}/forks`, {
        method: 'POST'
    });

    // Wait for fork to be ready (GitHub creates forks asynchronously)
    let attempts = 0;
    while (attempts < 10) {
        await new Promise(resolve => setTimeout(resolve, 2000));
        try {
            await githubRequest(`/repos/${fork.full_name}`);
            return fork;
        } catch (e) {
            attempts++;
        }
    }

    return fork;
}

/**
 * Get or create user's fork
 * @param {string} username - GitHub username
 * @returns {Promise<Object>} Fork info
 */
export async function getOrCreateFork(username) {
    const existing = await getUserFork(username);
    if (existing) {
        return existing;
    }
    return await createFork();
}

/**
 * Get the default branch's latest commit SHA
 * @param {string} owner - Repo owner
 * @param {string} repo - Repo name
 * @returns {Promise<string>} Commit SHA
 */
async function getLatestCommitSha(owner, repo) {
    const ref = await githubRequest(`/repos/${owner}/${repo}/git/ref/heads/${REPO_CONFIG.branch}`);
    return ref.object.sha;
}

/**
 * Create a new branch
 * @param {string} owner - Repo owner (user's fork)
 * @param {string} repo - Repo name
 * @param {string} branchName - New branch name
 * @param {string} baseSha - Base commit SHA
 * @returns {Promise<Object>} Branch ref
 */
async function createBranch(owner, repo, branchName, baseSha) {
    return await githubRequest(`/repos/${owner}/${repo}/git/refs`, {
        method: 'POST',
        body: JSON.stringify({
            ref: `refs/heads/${branchName}`,
            sha: baseSha
        })
    });
}

/**
 * Create or update a file in the repo
 * @param {string} owner - Repo owner
 * @param {string} repo - Repo name
 * @param {string} path - File path
 * @param {string} content - File content
 * @param {string} message - Commit message
 * @param {string} branch - Branch name
 * @param {string} existingSha - SHA of existing file (for updates)
 * @returns {Promise<Object>} Commit info
 */
async function createOrUpdateFile(owner, repo, path, content, message, branch, existingSha = null) {
    const body = {
        message,
        content: btoa(unescape(encodeURIComponent(content))), // Base64 encode with UTF-8 support
        branch
    };

    if (existingSha) {
        body.sha = existingSha;
    }

    return await githubRequest(`/repos/${owner}/${repo}/contents/${path}`, {
        method: 'PUT',
        body: JSON.stringify(body)
    });
}

/**
 * Get file info (to get SHA for updates)
 * @param {string} owner - Repo owner
 * @param {string} repo - Repo name
 * @param {string} path - File path
 * @param {string} branch - Branch name
 * @returns {Promise<Object|null>} File info or null
 */
async function getFileInfo(owner, repo, path, branch) {
    try {
        return await githubRequest(`/repos/${owner}/${repo}/contents/${path}?ref=${branch}`);
    } catch (e) {
        return null;
    }
}

/**
 * Create a pull request
 * @param {Object} options - PR options
 * @returns {Promise<Object>} PR info
 */
async function createPullRequest({ title, body, head, base }) {
    return await githubRequest(`/repos/${REPO_CONFIG.owner}/${REPO_CONFIG.repo}/pulls`, {
        method: 'POST',
        body: JSON.stringify({
            title,
            body,
            head,
            base,
            maintainer_can_modify: true
        })
    });
}

/**
 * Submit translations as a pull request
 * @param {Object} translationsByLang - Object with langCode keys and translations values
 * @param {Object} options - Options object
 * @param {Function} options.onProgress - Progress callback
 * @param {string} options.customTitle - Custom PR title (optional)
 * @param {string} options.customBody - Custom PR body (optional)
 * @param {Object} options.langNames - Map of langCode to display name
 * @returns {Promise<Object>} Result with PR URL
 */
export async function submitTranslationsPR(translationsByLang, options = {}) {
    const { onProgress = null, customTitle = null, customBody = null, langNames = {} } = options;
    if (!isGitHubAuthenticated()) {
        throw new Error('Not authenticated with GitHub');
    }

    const languages = Object.keys(translationsByLang);
    if (languages.length === 0) {
        throw new Error('No translations to submit');
    }

    // Get user info
    if (onProgress) onProgress('Getting user info...', 0);
    const user = await getGitHubUser();
    if (!user) {
        throw new Error('Failed to get GitHub user info');
    }

    // Get or create fork
    if (onProgress) onProgress('Checking for fork...', 10);
    const fork = await getOrCreateFork(user.login);

    // Get latest commit from upstream
    if (onProgress) onProgress('Getting latest commit...', 20);
    const baseSha = await getLatestCommitSha(REPO_CONFIG.owner, REPO_CONFIG.repo);

    // Create branch name
    const timestamp = Date.now();
    const langCodes = languages.join('-');
    const branchName = `translation/${langCodes}-${timestamp}`;

    // Create branch in fork
    if (onProgress) onProgress('Creating branch...', 30);
    await createBranch(user.login, REPO_CONFIG.repo, branchName, baseSha);

    // Commit translation files
    const totalFiles = languages.length * CATEGORIES.length * 2; // build42 + build41
    let filesCommitted = 0;

    for (const langCode of languages) {
        const translations = translationsByLang[langCode];
        const categorized = categorizeTranslations(translations);

        for (const category of CATEGORIES) {
            const categoryTranslations = categorized[category] || {};
            if (Object.keys(categoryTranslations).length === 0) continue;

            const fileContent = generateCategoryFile(category, langCode, translations);
            const filename = `${category}_${langCode}.txt`;

            // Build 42 path
            const build42Path = `${REPO_CONFIG.translationPaths.build42}/${langCode}/${filename}`;
            if (onProgress) onProgress(`Committing ${filename} (Build 42)...`, 30 + (filesCommitted / totalFiles) * 60);

            // Check if file exists to get SHA
            const existingFile42 = await getFileInfo(user.login, REPO_CONFIG.repo, build42Path, branchName);

            await createOrUpdateFile(
                user.login,
                REPO_CONFIG.repo,
                build42Path,
                fileContent,
                `Add/Update ${langCode} ${category} translation`,
                branchName,
                existingFile42?.sha
            );
            filesCommitted++;

            // Build 41 path
            const build41Path = `${REPO_CONFIG.translationPaths.build41}/${langCode}/${filename}`;
            if (onProgress) onProgress(`Committing ${filename} (Build 41)...`, 30 + (filesCommitted / totalFiles) * 60);

            const existingFile41 = await getFileInfo(user.login, REPO_CONFIG.repo, build41Path, branchName);

            await createOrUpdateFile(
                user.login,
                REPO_CONFIG.repo,
                build41Path,
                fileContent,
                `Add/Update ${langCode} ${category} translation`,
                branchName,
                existingFile41?.sha
            );
            filesCommitted++;
        }
    }

    // Create PR
    if (onProgress) onProgress('Creating pull request...', 95);

    const prTitle = customTitle || generatePRTitle(languages, langNames);
    const prBody = customBody || generatePRBody(languages, translationsByLang, langNames);

    const pr = await createPullRequest({
        title: prTitle,
        body: prBody,
        head: `${user.login}:${branchName}`,
        base: REPO_CONFIG.branch
    });

    if (onProgress) onProgress('Done!', 100);

    return {
        success: true,
        prUrl: pr.html_url,
        prNumber: pr.number,
        branchName,
        languages
    };
}

/**
 * Generate PR title
 * @param {string[]} languages - Array of language codes
 * @param {Object} langNames - Optional map of langCode to display name
 * @returns {string} PR title
 */
export function generatePRTitle(languages, langNames = {}) {
    const getDisplayName = (code) => langNames[code] || code;

    if (languages.length === 1) {
        return `Add/Update ${getDisplayName(languages[0])} translation`;
    } else if (languages.length <= 3) {
        return `Add/Update ${languages.map(getDisplayName).join(', ')} translations`;
    } else {
        return `Add/Update translations for ${languages.length} languages`;
    }
}

/**
 * Generate PR body
 * @param {string[]} languages - Array of language codes
 * @param {Object} translationsByLang - Translations by language
 * @param {Object} langNames - Optional map of langCode to display name
 * @returns {string} PR body
 */
export function generatePRBody(languages, translationsByLang, langNames = {}) {
    const english = getEnglishBaseline();
    const englishKeyCount = Object.keys(english).length;
    const getDisplayName = (code) => langNames[code] || code;

    let body = `## Translation Submission\n\n`;
    body += `This PR adds/updates translations for the following languages:\n\n`;

    for (const langCode of languages) {
        const translations = translationsByLang[langCode];
        const keyCount = Object.keys(translations).length;
        const percentage = Math.round((keyCount / englishKeyCount) * 100);
        body += `- **${getDisplayName(langCode)}** (${langCode}): ${keyCount} changed/new keys\n`;
    }

    body += `\n### Categories Updated\n\n`;

    for (const langCode of languages) {
        const translations = translationsByLang[langCode];
        const categorized = categorizeTranslations(translations);

        body += `**${getDisplayName(langCode)}:**\n`;
        for (const category of CATEGORIES) {
            const count = Object.keys(categorized[category] || {}).length;
            if (count > 0) {
                body += `- ${category}: ${count} keys\n`;
            }
        }
        body += `\n`;
    }

    body += `---\n`;
    body += `*Submitted via [Burd's Survival Journals Translation Tool](https://theburd.github.io/PZ-BurdSurvivalJournals/)*\n`;

    return body;
}

/**
 * Check if user can submit PR (has authentication and translations)
 * @param {Object} translationsByLang - Translations to submit
 * @returns {Object} Status info
 */
export function canSubmitPR(translationsByLang) {
    const isAuthenticated = isGitHubAuthenticated();
    const hasTranslations = translationsByLang && Object.keys(translationsByLang).length > 0;
    const hasContent = hasTranslations && Object.values(translationsByLang).some(
        t => Object.keys(t).length > 0
    );

    return {
        canSubmit: isAuthenticated && hasContent,
        isAuthenticated,
        hasTranslations: hasContent,
        reason: !isAuthenticated ? 'Not connected to GitHub' :
            !hasContent ? 'No translations to submit' : null
    };
}
