// test_dom.js — Puppeteer Headless DOM Verification
import puppeteer from 'puppeteer-core';
import { join } from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));

async function main() {
  console.log('\n=== Headless DOM Verification Loop ===');
  console.log('  • Launching Chrome...');
  
  let browser;
  try {
    browser = await puppeteer.launch({
      executablePath: 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
      headless: true,
      args: ['--no-sandbox', '--disable-setuid-sandbox']
    });
  } catch (err) {
    console.error('  ❌ Failed to launch Google Chrome:', err.message);
    process.exit(1);
  }

  console.log('  • Opening new tab...');
  const page = await browser.newPage();
  
  // Set viewport to a typical desktop size
  await page.setViewport({ width: 1280, height: 800 });

  page.on('console', msg => console.log('PAGE LOG:', msg.text()));
  page.on('pageerror', err => console.error('PAGE ERROR:', err.message));

  const url = 'http://localhost:8080';
  console.log(`  • Navigating to ${url}...`);
  
  try {
    // Navigate and wait for network idle to ensure Flutter Web engine finishes loading
    await page.goto(url, { waitUntil: 'networkidle2', timeout: 30000 });
    
    // Give Flutter 20 seconds extra padding to bootstrap the UI
    console.log('  • Waiting for Flutter engine bootstrap (20 seconds)...');
    await new Promise(resolve => setTimeout(resolve, 20000));
    
    // Read DOM details
    const title = await page.title();
    console.log(`  • Document Title: "${title}"`);
    
    // Capture visual screenshot of the rendered DOM (initial state)
    const screenshotPath = join(__dirname, '../admin_panel_live_capture.png');
    console.log(`  • Capturing page screenshot...`);
    await page.screenshot({ path: screenshotPath });
    console.log(`  • Screenshot saved successfully to: admin_panel_live_capture.png`);

    // Type into the token input
    console.log('  • Clicking at token input field coordinates (1130, 32)...');
    await page.mouse.click(1130, 32);
    await new Promise(resolve => setTimeout(resolve, 1000));

    console.log('  • Typing admin JWT token using native keyboard...');
    const token = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjNlNDU2Ny1lODliLTEyZDMtYTQ1Ni00MjY2MTQxNzQwMDAiLCJyb2xlIjoiYWRtaW4iLCJsb2NhbGUiOiJlbiIsImlhdCI6MTc3OTgyMjQ4NywiZXhwIjoxNzgyNDE0NDg3fQ.wnAvI5lp1eHsMM4JdejvTZklpKEZoTztq6LiBxXoees';
    await page.keyboard.type(token);
    
    console.log('  • Token entered. Waiting 5 seconds for mosques API call...');
    await new Promise(resolve => setTimeout(resolve, 5000));
      
      // Capture visual screenshot of the mosques loaded state
      const loadedScreenshotPath = join(__dirname, '../admin_panel_mosques_loaded.png');
      console.log(`  • Capturing loaded mosques screenshot...`);
      await page.screenshot({ path: loadedScreenshotPath });
      console.log(`  • Screenshot saved successfully to: admin_panel_mosques_loaded.png`);
      
  } catch (err) {
    console.error('  ❌ Navigation/Verification failed:', err.message);
  } finally {
    console.log('  • Closing Chrome...');
    await browser.close();
    console.log('=== Verification Loop Completed ===\n');
  }
}

main().catch(console.error);
