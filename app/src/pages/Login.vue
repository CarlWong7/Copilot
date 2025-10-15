<template>
  <section class="login">
    <div class="header">
      <button :class="{active: mode==='signin'}" @click="mode='signin'">Sign in</button>
      <button :class="{active: mode==='signup'}" @click="mode='signup'">Sign up</button>
    </div>

    <h2 v-if="mode==='signin'">Sign in</h2>
    <h2 v-else>Sign up</h2>

    <form @submit.prevent="onSubmit">
      <template v-if="mode==='signup'">
        <div class="form-row">
          <label class="muted">Full name</label>
          <input class="input" type="text" v-model="name" required />
        </div>
      </template>

      <div class="form-row">
        <label class="muted">Email</label>
        <input class="input" type="email" v-model="email" required />
      </div>

      <div class="form-row">
        <label class="muted">Password</label>
        <input class="input" type="password" v-model="password" required minlength="6" />
      </div>

      <template v-if="mode==='signup'">
        <div class="form-row">
          <label class="muted">Confirm password</label>
          <input class="input" type="password" v-model="confirm" required minlength="6" />
        </div>
      </template>

      <div class="actions">
        <button class="btn" type="submit">{{ mode === 'signin' ? 'Sign in' : 'Create account' }}</button>
      </div>
    </form>

    <div v-if="error" class="error">{{ error }}</div>
    <div v-if="success" class="success">{{ success }}</div>
  </section>
</template>

<script>
export default {
  name: 'Login',
  data() {
    return {
      mode: 'signin', // or 'signup'
      name: '',
      email: '',
      password: '',
      confirm: '',
      error: '',
      success: ''
    }
  },
  methods: {
    onSubmit() {
      this.error = ''
      this.success = ''

      if (!this.email) {
        this.error = 'Email is required.'
        return
      }
      if (this.password.length < 6) {
        this.error = 'Password must be at least 6 characters.'
        return
      }

      if (this.mode === 'signup') {
        if (!this.name) {
          this.error = 'Name is required for sign up.'
          return
        }
        if (this.password !== this.confirm) {
          this.error = 'Passwords do not match.'
          return
        }

        // Simulated signup
        this.success = `Account created for ${this.name} (${this.email}) — demo only.`
      } else {
        // Simulated signin
        this.success = `Signed in as ${this.email} — demo only.`
      }

      // Reset form fields (keep mode so user can see success)
      this.name = ''
      this.email = ''
      this.password = ''
      this.confirm = ''
    }
  }
}
</script>

<style scoped>
.login {
  border: 1px solid #e5e7eb;
  padding: 1.25rem;
  border-radius: 8px;
  background: #fff;
}
.header {
  display: flex;
  gap: 0.25rem;
  margin-bottom: 0.75rem;
}
.header button {
  padding: 0.4rem 0.75rem;
  border: 1px solid transparent;
  background: transparent;
  cursor: pointer;
}
.header button.active {
  border-color: #3b82f6;
  color: #1e3a8a;
  font-weight: 600;
}
.login h2 {
  margin: 0 0 1rem 0;
}
.login label {
  display: block;
  margin-bottom: 0.75rem;
}
.login input {
  width: 100%;
  padding: 0.5rem;
  box-sizing: border-box;
  margin-top: 0.25rem;
}
.actions {
  margin-top: 0.5rem;
}
.error { color: #b91c1c; margin-top: 0.75rem }
.success { color: #065f46; margin-top: 0.75rem }
</style>
