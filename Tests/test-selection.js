// Exercise the actual script from the Swift source using a minimal DOM fixture.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const source = fs.readFileSync('GoogleImageBrowser.swift','utf8').split('static let script = """')[1].split('"""')[0];
class HTMLImageElement {
  constructor(src, rect) { this.currentSrc = src; this.rect = rect; }
  getBoundingClientRect(){ return this.rect; }
  querySelectorAll(){return [];}
}
const rect = {left: 20, top:20, right:220,bottom:220,width:200,height:200};
const image = new HTMLImageElement('https://encrypted-tbn0.gstatic.com/example', rect);
const tiny = new HTMLImageElement('https://example.com/tiny', {left:50,top:50,right:60,bottom:60,width:10,height:10});
let messages = [], hit = [{querySelectorAll:()=>[tiny,image]}];
global.HTMLImageElement = HTMLImageElement;
global.window = {webkit:{messageHandlers:{iconSelection:{postMessage:x=>messages.push(x)}}}};
global.document = {elementsFromPoint:()=>hit,images:[tiny,image],addEventListener:()=>{}};
eval(source);
(async()=>{
 await window.__sifPickAt(55,55); assert.equal(messages.pop(),image.currentSrc);
 hit=[]; await window.__sifPickAt(100,100); assert.equal(messages.pop(),image.currentSrc);
 await window.__sifPickAt(300,300); assert.equal(messages.pop(),'');
 console.log('OK: image under overlay, document fallback, empty hit');
})().catch(e=>{console.error(e);process.exit(1)});
