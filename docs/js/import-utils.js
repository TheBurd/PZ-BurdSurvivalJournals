/**
 * Import Utilities
 * Handles importing translations from various formats
 */

import { parseLuaFile, validateTranslation } from './lua-parser.js';
import { getEnglishBaseline } from './translation-manager.js';

/**
 * Detect file type from content or filename
 * @param {string} content - File content
 * @param {string} filename - File name
 * @returns {string} File type: 'json', 'lua', 'zip', or 'unknown'
 */
export function detectFileType(content, filename = '') {
    const lowerName = filename.toLowerCase();

    // Check by extension first
    if (lowerName.endsWith('.json')) return 'json';
    if (lowerName.endsWith('.txt')) return 'lua';
    if (lowerName.endsWith('.zip')) return 'zip';

    // Try to detect from content
    const trimmed = content.trim();

    // JSON starts with { or [
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
            JSON.parse(content);
            return 'json';
        } catch (e) {
            // Not valid JSON
        }
    }

    // Lua table starts with identifier = {
    if (/^\w+\s*=\s*\{/m.test(trimmed)) {
        return 'lua';
    }

    return 'unknown';
}

/**
 * Parse JSON translation file (legacy format)
 * @param {string} content - JSON content
 * @returns {Object} Parse result
 */
export function parseJsonTranslations(content) {
    const result = {
        success: false,
        translations: {},
        metadata: {},
        errors: [],
        langCode: null
    };

    try {
        const data = JSON.parse(content);

        // Check for new format with _meta and translations
        if (data.translations && typeof data.translations === 'object') {
            result.translations = data.translations;
            result.metadata = data._meta || {};
            result.langCode = data._meta?.langCode || null;
        }
        // Check for multi-language format
        else if (data.languages && typeof data.languages === 'object') {
            result.translations = data.languages;
            result.metadata = data._meta || {};
            result.isMultiLanguage = true;
        }
        // Legacy format: flat object of key-value pairs
        else if (typeof data === 'object' && !Array.isArray(data)) {
            // Filter out metadata keys that start with _
            for (const [key, value] of Object.entries(data)) {
                if (!key.startsWith('_') && typeof value === 'string') {
                    result.translations[key] = value;
                } else if (key === '_meta' || key === 'langCode' || key === 'langName') {
                    result.metadata[key] = value;
                }
            }
            result.langCode = data.langCode || result.metadata?.langCode || null;
        }
        else {
            result.errors.push('Invalid JSON structure');
            return result;
        }

        result.success = true;
    } catch (error) {
        result.errors.push(`JSON parse error: ${error.message}`);
    }

    return result;
}

/**
 * Parse Lua translation file
 * @param {string} content - Lua file content
 * @param {string} filename - Original filename for category detection
 * @returns {Object} Parse result
 */
export function parseLuaTranslations(content, filename = '') {
    // Extract expected category from filename
    let expectedCategory = null;
    const match = filename.match(/^(\w+)_\w+\.txt$/i);
    if (match) {
        expectedCategory = match[1];
    }

    const parsed = parseLuaFile(content, expectedCategory);

    return {
        success: parsed.errors.length === 0 || Object.keys(parsed.translations).length > 0,
        translations: parsed.translations,
        langCode: parsed.langCode,
        category: parsed.tableName,
        errors: parsed.errors
    };
}

/**
 * Parse ZIP file containing translations
 * @param {File|Blob} file - ZIP file
 * @returns {Promise<Object>} Parse result
 */
export async function parseZipTranslations(file) {
    const result = {
        success: false,
        translations: {},
        files: [],
        langCode: null,
        errors: []
    };

    if (typeof JSZip === 'undefined') {
        result.errors.push('JSZip library not loaded');
        return result;
    }

    try {
        const zip = await JSZip.loadAsync(file);
        const txtFiles = [];

        // Find all .txt files in the ZIP
        zip.forEach((relativePath, zipEntry) => {
            if (!zipEntry.dir && relativePath.endsWith('.txt')) {
                txtFiles.push({ path: relativePath, entry: zipEntry });
            }
        });

        if (txtFiles.length === 0) {
            result.errors.push('No translation files (.txt) found in ZIP');
            return result;
        }

        // Process each .txt file
        for (const { path, entry } of txtFiles) {
            try {
                const content = await entry.async('string');
                const filename = path.split('/').pop();
                const parsed = parseLuaTranslations(content, filename);

                if (parsed.success) {
                    // Merge translations
                    Object.assign(result.translations, parsed.translations);
                    result.files.push({
                        path,
                        category: parsed.category,
                        langCode: parsed.langCode,
                        keyCount: Object.keys(parsed.translations).length
                    });

                    // Set langCode from first successful file
                    if (!result.langCode && parsed.langCode) {
                        result.langCode = parsed.langCode;
                    }
                } else {
                    result.errors.push(`${path}: ${parsed.errors.join(', ')}`);
                }
            } catch (e) {
                result.errors.push(`Failed to read ${path}: ${e.message}`);
            }
        }

        result.success = Object.keys(result.translations).length > 0;
    } catch (error) {
        result.errors.push(`ZIP error: ${error.message}`);
    }

    return result;
}

/**
 * Import from file input
 * @param {File} file - File object from input
 * @returns {Promise<Object>} Import result
 */
export async function importFromFile(file) {
    const result = {
        success: false,
        translations: {},
        langCode: null,
        format: 'unknown',
        errors: [],
        warnings: []
    };

    const filename = file.name;

    // Handle ZIP files
    if (filename.toLowerCase().endsWith('.zip')) {
        const zipResult = await parseZipTranslations(file);
        result.format = 'zip';
        result.translations = zipResult.translations;
        result.langCode = zipResult.langCode;
        result.success = zipResult.success;
        result.errors = zipResult.errors;
        result.files = zipResult.files;
        return result;
    }

    // Read file as text
    const content = await readFileAsText(file);

    // Detect and parse
    const fileType = detectFileType(content, filename);
    result.format = fileType;

    if (fileType === 'json') {
        const jsonResult = parseJsonTranslations(content);
        result.translations = jsonResult.translations;
        result.langCode = jsonResult.langCode;
        result.success = jsonResult.success;
        result.errors = jsonResult.errors;
        result.isMultiLanguage = jsonResult.isMultiLanguage;
    } else if (fileType === 'lua') {
        const luaResult = parseLuaTranslations(content, filename);
        result.translations = luaResult.translations;
        result.langCode = luaResult.langCode;
        result.success = luaResult.success;
        result.errors = luaResult.errors;
    } else {
        result.errors.push('Unknown file format');
    }

    return result;
}

/**
 * Read file as text
 * @param {File} file - File object
 * @returns {Promise<string>} File content
 */
function readFileAsText(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result);
        reader.onerror = () => reject(reader.error);
        reader.readAsText(file);
    });
}

/**
 * Validate imported translations against English baseline
 * @param {Object} translations - Imported translations
 * @returns {Object} Validation result
 */
export function validateImportedTranslations(translations) {
    const english = getEnglishBaseline();
    const englishKeys = Object.keys(english);
    const importedKeys = Object.keys(translations);

    const result = {
        valid: [],
        warnings: [],
        missing: [],
        extra: [],
        placeholderIssues: []
    };

    // Check each imported key
    for (const key of importedKeys) {
        if (englishKeys.includes(key)) {
            const validation = validateTranslation(key, translations[key], english[key]);
            if (validation.valid) {
                result.valid.push(key);
            } else {
                result.placeholderIssues.push({
                    key,
                    warnings: validation.warnings
                });
            }
        } else {
            result.extra.push(key);
        }
    }

    // Check for missing keys
    for (const key of englishKeys) {
        if (!importedKeys.includes(key)) {
            result.missing.push(key);
        }
    }

    return result;
}

/**
 * Merge imported translations with existing
 * @param {Object} existing - Existing translations
 * @param {Object} imported - Imported translations
 * @param {string} mode - Merge mode: 'overwrite', 'skip', 'fill'
 * @returns {Object} Merged translations
 */
export function mergeTranslations(existing, imported, mode = 'fill') {
    const merged = { ...existing };

    for (const [key, value] of Object.entries(imported)) {
        switch (mode) {
            case 'overwrite':
                // Always use imported value
                merged[key] = value;
                break;
            case 'skip':
                // Only add if key doesn't exist
                if (!(key in merged)) {
                    merged[key] = value;
                }
                break;
            case 'fill':
            default:
                // Only add if key doesn't exist or existing value is empty
                if (!(key in merged) || !merged[key] || !merged[key].trim()) {
                    merged[key] = value;
                }
                break;
        }
    }

    return merged;
}

/**
 * Create a file input and trigger it
 * @param {string} accept - Accepted file types
 * @param {boolean} multiple - Allow multiple files
 * @returns {Promise<FileList>} Selected files
 */
export function openFileDialog(accept = '.json,.txt,.zip', multiple = false) {
    return new Promise((resolve) => {
        const input = document.createElement('input');
        input.type = 'file';
        input.accept = accept;
        input.multiple = multiple;

        input.onchange = () => {
            resolve(input.files);
        };

        input.click();
    });
}

/**
 * Handle drag and drop file import
 * @param {DragEvent} event - Drag event
 * @returns {Promise<Object[]>} Array of import results
 */
export async function handleDrop(event) {
    event.preventDefault();

    const files = event.dataTransfer?.files;
    if (!files || files.length === 0) {
        return [];
    }

    const results = [];
    for (const file of files) {
        const result = await importFromFile(file);
        result.filename = file.name;
        results.push(result);
    }

    return results;
}

/**
 * Get import summary for UI display
 * @param {Object} importResult - Result from importFromFile
 * @param {Object} validationResult - Result from validateImportedTranslations
 * @returns {Object} Summary for display
 */
export function getImportSummary(importResult, validationResult) {
    return {
        format: importResult.format,
        langCode: importResult.langCode,
        totalKeys: Object.keys(importResult.translations).length,
        validKeys: validationResult.valid.length,
        missingKeys: validationResult.missing.length,
        extraKeys: validationResult.extra.length,
        placeholderIssues: validationResult.placeholderIssues.length,
        hasErrors: importResult.errors.length > 0,
        errors: importResult.errors
    };
}
