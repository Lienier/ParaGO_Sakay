// Schema documentation only: no database connection and no environment secrets.
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..');
function paths(schema, prefix = '') {
  return Object.entries(schema.paths).flatMap(([name, type]) => {
    const item = { path: prefix + name, type: type.instance, required: !!type.isRequired,
      ...(type.options.ref ? { ref: type.options.ref } : {}),
      ...(type.enumValues?.length ? { enum: type.enumValues } : {}) };
    return [item, ...(type.schema ? paths(type.schema, prefix + name + '.') : [])];
  });
}
const models = fs.readdirSync(path.join(root, 'src/models')).filter(f => f.endsWith('.js')).map(file => {
  const m = require(path.join(root, 'src/models', file));
  return { file, model: m.modelName, collection: m.collection.name, paths: paths(m.schema), indexes: m.schema.indexes() };
});
fs.writeFileSync(path.join(root, 'artifacts/diagrams/ParaGO_schema_reference.json'), JSON.stringify(models, null, 2) + '\n');
console.log(`Exported ${models.length} schema definitions; no database connection.`);
process.exit(0);
