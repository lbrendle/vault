import {flushSync} from 'react-dom';
// Each pane owns its animation. Capturing the whole WKWebView also captures
// the rail and native title-bar area, leaving stale colors and doubled controls
// when navigation, a theme change, and a panel resize happen together.
export function transition(update) { flushSync(update); }
