// Links are stored as raw owner text. They are never fetched by the server.
export function checkedModelUrl(value) {
  if (typeof value !== 'string' || value.length > 4000) throw new Error('Ссылка на модель: максимум 4000 символов.');
  if (value === '') return value;
  let url;
  try { url = new URL(value); } catch { throw new Error('Укажи полный HTTP / HTTPS URL модели.'); }
  if (!['http:', 'https:'].includes(url.protocol) || !url.hostname || url.username || url.password) throw new Error('Ссылка на модель должна быть HTTP / HTTPS без логина и пароля.');
  return value;
}
