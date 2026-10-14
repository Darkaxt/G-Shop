uniform FragInfo {
  vec4 color;
  vec4 pbr; // roughness, metallic, normal depth, casing tint strength
  vec4 uv_info; // scale, offset xy, albedo impact
  vec4 flags; // casing shader, label, disc metal, AO strength
  vec4 channels; // source roughness, metallic and AO channel selectors
} material;
uniform sampler2D albedo_map;
uniform sampler2D roughness_map;
uniform sampler2D metallic_map;
uniform sampler2D normal_map;
uniform sampler2D ao_map;
in vec3 v_position;
in vec3 v_normal;
in vec2 v_uv;
out vec4 frag_color;

float source_channel(vec4 sampled, float channel) {
  if (channel < 0.5) return sampled.r;
  if (channel < 1.5) return sampled.g;
  if (channel < 2.5) return sampled.b;
  if (channel < 3.5) return sampled.a;
  return dot(sampled.rgb, vec3(0.333333));
}

void main() {
  vec2 uv = v_uv * material.uv_info.x + material.uv_info.yz;
  vec4 sampled = texture(albedo_map, uv);
  if (material.flags.y > 0.5) sampled.rgb /= max(sampled.a, 0.00001);
  vec3 base = sampled.rgb * material.color.rgb;
  if (material.flags.x > 0.5) {
    vec3 textured = mix(vec3(1.0), sampled.rgb, material.uv_info.w);
    float luma = dot(textured, vec3(0.299, 0.587, 0.114));
    base = mix(textured, material.color.rgb * luma, material.pbr.w);
  }
  float alpha = sampled.a * material.color.a;
  if (alpha < 0.002) discard;
  vec3 n = normalize(v_normal);
  vec3 tangentNormal = texture(normal_map, uv).xyz * 2.0 - 1.0;
  tangentNormal.xy *= material.pbr.z;
  vec3 dp1 = dFdx(v_position), dp2 = dFdy(v_position);
  vec2 duv1 = dFdx(uv), duv2 = dFdy(uv);
  vec3 t = dp1 * duv2.y - dp2 * duv1.y;
  vec3 b = -dp1 * duv2.x + dp2 * duv1.x;
  float invLength = inversesqrt(max(max(dot(t, t), dot(b, b)), 0.000001));
  n = normalize(mat3(t * invLength, b * invLength, n) * tangentNormal);
  if (!gl_FrontFacing) n = -n;
  vec3 view = normalize(vec3(0.0, 0.0, 4.0) - v_position);
  // Socket main scene's DirectionalLight3D +Z, transformed by its -Z camera.
  // The prior invented bottom-side light shadowed the tilted cartridge front.
  vec3 light = normalize(vec3(0.3154230118, 0.8141155243, 0.4875697494));
  vec3 halfVector = normalize(view + light);
  float ndl = max(dot(n, light), 0.0), ndv = max(dot(n, view), 0.001);
  float ndh = max(dot(n, halfVector), 0.0), vdh = max(dot(view, halfVector), 0.0);
  float rough = clamp(source_channel(texture(roughness_map, uv), material.channels.x) * material.pbr.x, 0.045, 1.0);
  float metal = clamp(source_channel(texture(metallic_map, uv), material.channels.y) * material.pbr.y, 0.0, 1.0);
  float ao = mix(1.0, source_channel(texture(ao_map, uv), material.channels.z), material.flags.w);
  vec3 f0 = mix(vec3(0.04), base, metal);
  vec3 fresnel = f0 + (1.0 - f0) * pow(1.0 - vdh, 5.0);
  float a2 = pow(rough, 4.0);
  float denom = ndh * ndh * (a2 - 1.0) + 1.0;
  float distribution = a2 / max(3.14159265 * denom * denom, 0.00001);
  float k = (rough + 1.0) * (rough + 1.0) / 8.0;
  float geometry = ndl / (ndl * (1.0 - k) + k) * ndv / (ndv * (1.0 - k) + k);
  vec3 specular = distribution * geometry * fresnel / max(4.0 * ndl * ndv, 0.001);
  vec3 lit = (base * (1.0 - metal) * ndl + specular * ndl) * 0.85 + base * 0.35 * ao;
  if (material.flags.z > 0.5) {
    float angle = atan(v_uv.y - 0.5, v_uv.x - 0.5) + dot(n, view) * 8.0;
    vec3 rainbow = 0.5 + 0.5 * cos(angle + vec3(0.0, 2.094, 4.188));
    lit += rainbow * pow(1.0 - ndv, 2.0) * 0.2;
  }
  frag_color = vec4(lit * alpha, alpha);
}
