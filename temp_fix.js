const fs = require('fs');
const path = 'd:/ZJY/Code/ChatCategorize/entry/src/main/ets/pages/Index.ets';
let c = fs.readFileSync(path, 'utf8');
// Fix: 3 single quotes -> 2 single quotes for empty string
c = c.replace(/new Conversation\(0, '''''\)/g, 'new Conversation(0, \x27\x27)');
c = c.replace(/\.trim\(\) === '''''/g, '.trim() === \x27\x27');
c = c.replace(/this\.inputText = '''''/g, 'this.inputText = \x27\x27');
fs.writeFileSync(path, c, 'utf8');
console.log('done');
