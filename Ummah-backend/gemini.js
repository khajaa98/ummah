// gemini.js
// =============================================================================
// Google Gemini AI client singleton.
//
// Model selection: gemini-1.5-flash
//   • Best price/performance ratio for multimodal OCR tasks
//   • 1M token context window handles large timetable images
//   • Significantly faster than Pro for structured extraction tasks
//
// NOTE: The server is started with `node --env-file=.env server.js` so
// GEMINI_API_KEY is already in process.env — no dotenv import needed here.
// The guard below is a runtime safety check, not a loader.
// =============================================================================

import { GoogleGenerativeAI } from '@google/generative-ai';

const GEMINI_API_KEY = process.env.GEMINI_API_KEY;

if (!GEMINI_API_KEY || GEMINI_API_KEY === 'your_actual_api_key_here') {
  // Warn loudly at startup — the pipeline won't work without this
  console.warn(
    '[Gemini] ⚠️  GEMINI_API_KEY is not set in .env. ' +
    'The OCR upload endpoint will return 503 until this is configured. ' +
    'Get a key at https://aistudio.google.com/app/apikey',
  );
}

const genAI = new GoogleGenerativeAI(GEMINI_API_KEY ?? '');

// gemini-1.5-flash: fast, cost-effective, strong at structured OCR extraction
export const geminiVision = genAI.getGenerativeModel({
  model: 'gemini-1.5-flash',
  generationConfig: {
    // Force pure JSON output — reduces probability of markdown wrapping
    responseMimeType: 'application/json',
    temperature:      0.1,   // low creativity = high accuracy for data extraction
    topP:             0.8,
  },
});
