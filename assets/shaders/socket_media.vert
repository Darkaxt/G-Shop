uniform VertInfo {
  mat4 mvp;
  mat4 model;
  mat4 normal_matrix;
} vert_info;

in vec3 position;
in vec3 normal;
in vec2 texture_coords;
out vec3 v_position;
out vec3 v_normal;
out vec2 v_uv;

void main() {
  v_position = (vert_info.model * vec4(position, 1.0)).xyz;
  v_normal = normalize((vert_info.normal_matrix * vec4(normal, 0.0)).xyz);
  v_uv = texture_coords;
  gl_Position = vert_info.mvp * vec4(position, 1.0);
}
