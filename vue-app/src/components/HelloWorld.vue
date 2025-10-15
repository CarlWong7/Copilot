<template>
  <section>
    <p>{{ msg }}</p>
    <button @click="count++">You clicked me {{ count }} times</button>
  </section>
</template>

<script>
export default {
  name: 'HelloWorld',
  props: {
    msg: String
  },
  data() {
    return { count: 0 }
  }
}
</script>

<style scoped>
button {
  margin-top: 0.5rem;
  padding: 0.5rem 1rem;
}
</style>
