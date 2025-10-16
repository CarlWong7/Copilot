import React, { useState } from 'react'
import { useNavigate } from 'react-router-dom'

export default function SignUp() {
  const [username, setUsername] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const navigate = useNavigate()

  function handleSubmit(e) {
    e.preventDefault()
    if (!username) return
    // Minimal client-side signup: store username in localStorage
    localStorage.setItem('username', username)
    // In a real app you'd send email/password to a server here.
    navigate('/')
  }

  return (
    <div>
      <h2>Create account</h2>
      <form onSubmit={handleSubmit}>
        <label>
          Username
          <input value={username} onChange={(e) => setUsername(e.target.value)} placeholder="username" />
        </label>
        <label>
          Email
          <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="you@example.com" />
        </label>
        <label>
          Password
          <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="password" />
        </label>
        <div style={{ marginTop: 8 }}>
          <button type="submit" className="btn">Create account</button>
        </div>
      </form>
    </div>
  )
}
