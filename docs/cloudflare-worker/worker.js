/**
 * Burd's Survival Journals - GitHub OAuth Proxy
 * Cloudflare Worker for securely exchanging OAuth codes for tokens
 *
 * Environment Variables (set via wrangler secret):
 * - GITHUB_CLIENT_ID: Your GitHub OAuth App Client ID
 * - GITHUB_CLIENT_SECRET: Your GitHub OAuth App Client Secret
 * - ALLOWED_ORIGINS: Comma-separated list of allowed origins (e.g., "https://theburd.github.io")
 */

const GITHUB_OAUTH_URL = 'https://github.com/login/oauth/access_token';

// CORS headers
function getCorsHeaders(origin) {
    const allowedOrigins = (ALLOWED_ORIGINS || 'https://theburd.github.io').split(',').map(o => o.trim());

    // Check if origin is allowed
    const isAllowed = allowedOrigins.includes(origin) ||
                      allowedOrigins.includes('*') ||
                      origin?.includes('localhost');

    return {
        'Access-Control-Allow-Origin': isAllowed ? origin : allowedOrigins[0],
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Access-Control-Max-Age': '86400',
    };
}

// Handle CORS preflight
function handleOptions(request) {
    const origin = request.headers.get('Origin');
    return new Response(null, {
        status: 204,
        headers: getCorsHeaders(origin)
    });
}

// Main handler
export default {
    async fetch(request, env) {
        const url = new URL(request.url);
        const origin = request.headers.get('Origin');
        const corsHeaders = getCorsHeaders(origin);

        // Handle CORS preflight
        if (request.method === 'OPTIONS') {
            return handleOptions(request);
        }

        // Route: POST /token - Exchange code for access token
        if (url.pathname === '/token' && request.method === 'POST') {
            try {
                const body = await request.json();
                const { code, state } = body;

                if (!code) {
                    return new Response(JSON.stringify({ error: 'Missing code parameter' }), {
                        status: 400,
                        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
                    });
                }

                // Exchange code for token with GitHub
                const tokenResponse = await fetch(GITHUB_OAUTH_URL, {
                    method: 'POST',
                    headers: {
                        'Accept': 'application/json',
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({
                        client_id: env.GITHUB_CLIENT_ID,
                        client_secret: env.GITHUB_CLIENT_SECRET,
                        code: code
                    })
                });

                const tokenData = await tokenResponse.json();

                // Return token to client
                return new Response(JSON.stringify(tokenData), {
                    status: tokenResponse.ok ? 200 : 400,
                    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
                });
            } catch (error) {
                return new Response(JSON.stringify({ error: error.message }), {
                    status: 500,
                    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
                });
            }
        }

        // Route: GET /health - Health check
        if (url.pathname === '/health') {
            return new Response(JSON.stringify({
                status: 'ok',
                timestamp: new Date().toISOString()
            }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' }
            });
        }

        // 404 for unknown routes
        return new Response(JSON.stringify({ error: 'Not found' }), {
            status: 404,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
    }
};
