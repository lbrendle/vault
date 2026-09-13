import React, {useState} from 'react';
import {Hash, Pencil, Check, X} from 'lucide-react';
import {isTagProperty, propertyTags, propertyText, propertyDraft, parsePropertyDraft} from './propertyValues';

export default function Properties({properties, onChange}) {
  const [editing, setEditing] = useState(null);
  const [draft, setDraft] = useState('');
  const [error, setError] = useState('');
  const entries = Object.entries(properties);
  function begin(key, value) {
    setEditing(key); setDraft(propertyDraft(key, value)); setError('');
  }
  function commit(key, value) {
    try { onChange(key, parsePropertyDraft(key, draft, value)); setEditing(null); setError(''); }
    catch (e) { setError(e.message); }
  }
  return <details className="properties document-properties">
    <summary>Properties <span>{entries.length}</span></summary>
    <div className="property-list">{entries.map(([key, value]) => <div className="property-row" key={key}>
      <span className="property-name">{isTagProperty(key) && <Hash size={14}/>}<span>{key}</span></span>
      {editing === key ? <div className="property-editor">
        <textarea aria-label={'Edit ' + key} value={draft} autoFocus rows={isTagProperty(key) ? 2 : 3}
          onChange={e => setDraft(e.target.value)} onKeyDown={e => {
            if (e.key === 'Escape') { e.preventDefault(); setEditing(null); }
            if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) { e.preventDefault(); commit(key, value); }
          }}/>
        {isTagProperty(key) && <small>Separate tags with commas. Use / for nested tags.</small>}
        {error && <p role="alert">{error}</p>}
        <div className="property-editor-actions"><button onClick={() => commit(key, value)}><Check size={14}/> Save</button><button onClick={() => setEditing(null)}><X size={14}/> Cancel</button></div>
      </div> : <button className="property-value" aria-label={'Edit ' + key} onClick={() => begin(key, value)}>
        {isTagProperty(key) ? <span className="property-tags">{propertyTags(value).map(tag => <span className="property-tag" key={tag}><span aria-hidden="true">#</span>{tag}</span>)}{!propertyTags(value).length && <span className="property-empty">No tags</span>}</span>
          : <span className="property-content">{Array.isArray(value) ? value.map(propertyText).join(' · ') : propertyText(value) || <span className="property-empty">Empty</span>}</span>}
        <Pencil className="property-edit-icon" size={13}/>
      </button>}
    </div>)}</div>
  </details>;
}
