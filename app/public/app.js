export function mountNotesUi({ document, fetchFn = globalThis.fetch }) {
  const form = document.querySelector('#note-form');
  const text = document.querySelector('#note-text');
  const list = document.querySelector('#notes-list');
  const emptyState = document.querySelector('#empty-state');
  const message = document.querySelector('#message');
  const cancelEdit = document.querySelector('#cancel-edit');
  let editingId = null;

  function setMessage(value, isSuccess = false) {
    message.textContent = value;
    message.classList.toggle('success', isSuccess);
  }

  function resetEditor() {
    editingId = null;
    text.value = '';
    cancelEdit.hidden = true;
    form.querySelector('button[type="submit"]').textContent = 'Save note';
  }

  async function request(url, options) {
    const response = await fetchFn(url, options);
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      throw new Error(body.error || 'Request failed');
    }
    return response.status === 204 ? null : response.json();
  }

  function renderNotes(notes) {
    list.replaceChildren();
    emptyState.hidden = notes.length > 0;
    for (const note of notes) {
      const item = document.createElement('li');
      const content = document.createElement('div');
      const noteText = document.createElement('p');
      const date = document.createElement('p');
      const actions = document.createElement('div');
      const edit = document.createElement('button');
      const remove = document.createElement('button');
      noteText.className = 'note-text';
      noteText.textContent = note.text;
      date.className = 'note-date';
      date.textContent = new Date(note.created_at).toLocaleString();
      edit.textContent = 'Edit';
      remove.textContent = 'Delete';
      remove.className = 'secondary danger';
      actions.className = 'note-actions';
      edit.addEventListener('click', () => {
        editingId = note.id;
        text.value = note.text;
        cancelEdit.hidden = false;
        form.querySelector('button[type="submit"]').textContent = 'Update note';
        text.focus();
      });
      remove.addEventListener('click', async () => {
        try {
          await request(`/notes/${note.id}`, { method: 'DELETE' });
          setMessage('Note deleted.', true);
          await loadNotes();
        } catch (error) {
          setMessage(error.message);
        }
      });
      content.append(noteText, date);
      actions.append(edit, remove);
      item.append(content, actions);
      list.append(item);
    }
  }

  async function loadNotes() {
    try {
      renderNotes(await request('/notes'));
    } catch (error) {
      setMessage(`Could not load notes: ${error.message}`);
    }
  }

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    const value = text.value.trim();
    if (!value) {
      setMessage('Note text is required.');
      return;
    }
    try {
      const isEditing = editingId !== null;
      await request(isEditing ? `/notes/${editingId}` : '/notes', {
        method: isEditing ? 'PATCH' : 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ text: value })
      });
      setMessage(isEditing ? 'Note updated.' : 'Note saved.', true);
      resetEditor();
      await loadNotes();
    } catch (error) {
      setMessage(error.message);
    }
  });

  cancelEdit.addEventListener('click', resetEditor);
  document.querySelector('#refresh-notes').addEventListener('click', loadNotes);
  fetchFn('/version')
    .then((response) => response.json())
    .then(({ version }) => { document.querySelector('#deployment-version').textContent = `Deployment version: ${version}`; })
    .catch(() => { document.querySelector('#deployment-version').textContent = 'Deployment version: unavailable'; });
  loadNotes();
  return { loadNotes };
}

if (globalThis.document?.querySelector('#notes-app')) {
  mountNotesUi({ document: globalThis.document });
}
