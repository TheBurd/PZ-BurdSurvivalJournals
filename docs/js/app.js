/**
 * Burd's Survival Journals Translation Tool
 * Main Application Entry Point
 */

import { initUI } from './ui-controller.js';

// Initialize app when DOM is ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
} else {
    init();
}

async function init() {
    console.log("Burd's Survival Journals Translation Tool v3.0");
    console.log('Initializing...');

    try {
        await initUI();
        console.log('Initialization complete!');
    } catch (error) {
        console.error('Failed to initialize:', error);

        // Show error to user
        const container = document.getElementById('translationContainer');
        if (container) {
            container.innerHTML = `
                <div class="error-state">
                    <h3>Failed to Load</h3>
                    <p>${error.message}</p>
                    <button onclick="location.reload()" class="btn btn-primary">Retry</button>
                </div>
            `;
        }
    }
}
