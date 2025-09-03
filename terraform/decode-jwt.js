#!/usr/bin/env node

const fs = require('fs');

const jwt = fs.readFileSync('/Users/steverhoton/git/tmp/jwt_file', 'utf8').trim();
const parts = jwt.split('.');

if (parts.length === 3) {
  const payload = JSON.parse(Buffer.from(parts[1], 'base64').toString());
  console.log('JWT Payload:');
  console.log(JSON.stringify(payload, null, 2));
  console.log('\nKey fields:');
  console.log('  Issuer:', payload.iss);
  console.log('  Audience:', JSON.stringify(payload.aud));
  console.log('  Subject:', payload.sub);
}