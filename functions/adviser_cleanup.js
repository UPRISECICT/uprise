// Deletes assignments for one organization, never by adviser name or email.
async function deleteOrganizationAdviserRoles(db, orgId) {
  const query = db.collection('adviser_roles').where('orgId', '==', orgId).limit(400);
  let deleted = 0;
  while (true) {
    const snapshot = await query.get();
    if (snapshot.empty) return deleted;
    const batch = db.batch();
    for (const doc of snapshot.docs) batch.delete(doc.ref);
    await batch.commit();
    deleted += snapshot.docs.length;
  }
}

module.exports = {deleteOrganizationAdviserRoles};
