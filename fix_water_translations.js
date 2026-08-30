const fs = require('fs');
const path = './lib/services/app_localizations.dart';
let content = fs.readFileSync(path, 'utf8');

// For each language, the water entries were placed AFTER the closing }, 
// They need to be moved INSIDE the map, BEFORE the closing },
// Current bad pattern: "    },\n      'Water Intake': ...\n    },\n    'NextLang': {"
// Should be: "      'Water Intake': ...\n    },\n    'NextLang': {"

const waterKeys = [
  "'Water Intake'",
  "'glasses'",
  "'Set Water Goal'",
  "'Remove glass'",
  "'Add glass'",
  "'250ml per glass'",
  "'Goal reached!'",
  "'remaining'",
  "'Water goal reached!",
];

// Remove each misplaced block: "    },\n      'Water...stayed hydrated!',\n    },\n    'Telugu': {" -> "    },\n    'Telugu': {"
// And re-add them before the }, 

const langPairs = [
  ['Tamil', 'Telugu'],
  ['Telugu', 'Kannada'],
  ['Kannada', 'Malayalam'],
  ['Malayalam', 'Hindi'],
  ['Hindi', 'Marathi'],
  ['Marathi', 'Urdu'],
  ['Urdu', 'French'],
  ['French', 'Japanese'],
];

for (const [fromLang, toLang] of langPairs) {
  // Find the bad pattern: },\n      'Water Intake'... },\n    'NextLang': {
  // and fix to: },\n    'NextLang': { (remove misplaced block)
  const badPattern = `    },\n      'Water Intake':`;
  const idx = content.indexOf(badPattern);
  if (idx === -1) continue;
  
  // Find the end of this misplaced block (the next "    },\n    '" that follows)
  const afterBad = content.substring(idx + 6); // skip "    },\n"
  const nextLangIdx = afterBad.indexOf(`    },\n    '${toLang}': {`);
  if (nextLangIdx === -1) {
    const nextLangIdx2 = afterBad.indexOf(`    },\r\n    '${toLang}': {`);
    if (nextLangIdx2 === -1) continue;
  }
  
  // Extract the misplaced water translations
  const blockStart = idx + 6; // start of "      'Water Intake'..."
  const nextLangSearch = afterBad.indexOf(`,\n    '${toLang}': {`);
  const nextLangSearch2 = afterBad.indexOf(`,\r\n    '${toLang}': {`);
  let blockEnd;
  if (nextLangSearch !== -1) blockEnd = idx + 6 + nextLangSearch;
  else if (nextLangSearch2 !== -1) blockEnd = idx + 6 + nextLangSearch2;
  else continue;
  
  // Extract the water translation lines
  const waterBlock = content.substring(blockStart, blockEnd).trim();
  
  // Remove the misplaced block from content  
  content = content.substring(0, idx) + `    },\n    '${toLang}': {` + content.substring(blockEnd + 2);
  
  // Now insert the water translations BEFORE the closing }, of fromLang
  // Find "    },\n    '${toLang}'" and insert before "    },"
  const insertPattern = `    },\n    '${toLang}': {`;
  const insertIdx = content.indexOf(insertPattern);
  if (insertIdx === -1) continue;
  
  // Add water translations before the },
  content = content.substring(0, insertIdx) + waterBlock + '\n' + content.substring(insertIdx);
  
  console.log(`Fixed ${fromLang}: moved water translations inside the map`);
}

// Handle Japanese (last language) - misplaced at end of file
const jpBadPattern = `    },\n      'Water Intake':`;
const jpIdx = content.lastIndexOf(jpBadPattern);
if (jpIdx !== -1) {
  // Find the end of the misplaced block
  const jpAfter = content.substring(jpIdx + 6);
  const jpEnd = jpAfter.indexOf(`\n  };`);
  if (jpEnd !== -1) {
    const jpWaterBlock = jpAfter.substring(0, jpEnd).trim();
    // Remove misplaced block
    content = content.substring(0, jpIdx) + content.substring(jpIdx + 6 + jpEnd);
    
    // Find the last },  before "  };" and insert
    const lastClosing = content.lastIndexOf('    },\n  };');
    if (lastClosing !== -1) {
      content = content.substring(0, lastClosing) + jpWaterBlock + '\n' + content.substring(lastClosing);
    }
    console.log('Fixed Japanese: moved water translations inside the map');
  }
}

fs.writeFileSync(path, content, 'utf8');
console.log('Done fixing!');
