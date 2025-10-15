<template>
  <div class="app-shell">
    <div class="card">
      <Login />
    </div>
  </div>
</template>

<script>
import Login from './pages/Login.vue'

export default {
  name: 'App',
  components: { Login }
}
</script>

<style>
/* layout handled by global styles */
</style>
