const {test} = require('node:test');
const assert = require('node:assert/strict');
const {deleteOrganizationAdviserRoles} = require('./adviser_cleanup');

function fakeDatabase(records) {
  const rows = new Map(records.map((row) => [row.id, row]));
  let commits = 0;
  return {
    rows,
    get commits() { return commits; },
    collection(name) {
      assert.equal(name, 'adviser_roles');
      return {where(field, operator, orgId) {
        assert.equal(field, 'orgId');
        assert.equal(operator, '==');
        return {limit(size) {
          return {async get() {
            const docs = [...rows.values()].filter((r) => r.orgId === orgId)
                .slice(0, size).map((r) => ({ref: r.id}));
            return {docs, empty: docs.length === 0};
          }};
        }};
      }};
    },
    batch() {
      const pending = [];
      return {
        delete(ref) { pending.push(ref); },
        async commit() {
          assert.ok(pending.length <= 400);
          pending.forEach((id) => rows.delete(id));
          commits++;
        },
      };
    },
  };
}

test('removes active and archived assignments only for the deleted org', async () => {
  const db = fakeDatabase([
    {id: 'a', orgId: 'deleted', email: 'same@example.com', archived: false},
    {id: 'b', orgId: 'deleted', archived: true},
    {id: 'c', orgId: 'existing', email: 'same@example.com'},
  ]);
  assert.equal(await deleteOrganizationAdviserRoles(db, 'deleted'), 2);
  assert.deepEqual([...db.rows.keys()], ['c']);
  assert.equal(await deleteOrganizationAdviserRoles(db, 'deleted'), 0);
});

test('cleans more than one batch without exceeding the write limit', async () => {
  const db = fakeDatabase(Array.from({length: 805}, (_, id) => ({id, orgId: 'org'})));
  assert.equal(await deleteOrganizationAdviserRoles(db, 'org'), 805);
  assert.equal(db.commits, 3);
});

test('propagates write failures so the trigger can retry', async () => {
  const db = fakeDatabase([{id: 'a', orgId: 'org'}]);
  db.batch = () => ({delete() {}, async commit() { throw new Error('unavailable'); }});
  await assert.rejects(deleteOrganizationAdviserRoles(db, 'org'), /unavailable/);
});
