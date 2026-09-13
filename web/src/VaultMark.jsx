import React from 'react';
// The folded V is drawn as a mark, without the app icon’s square container.
export default function VaultMark({size=30,className=''}){return <svg className={'vault-mark '+className} width={size} height={size} viewBox="0 0 32 32" fill="none" aria-hidden="true"><path d="M4 5.5C9.1 6.4 12.2 9.4 15.1 13.4L16 27C11.1 24.7 6.4 17.4 4 5.5Z" fill="currentColor" opacity=".48"/><path d="M28 3.5C22.5 5.2 18.8 8.7 16.8 13.2L16 27C21.1 22.9 25.7 14.8 28 3.5Z" fill="currentColor"/><path d="M10 5.2L16.7 10.4L16 23.3L14.1 12.4L10 5.2Z" fill="currentColor" opacity=".23"/></svg>}
