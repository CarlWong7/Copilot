import React, { useState } from 'react'
import { useNavigate, Link } from 'react-router-dom'

export default function Login() {
  const [username, setUsername] = useState('')
  const navigate = useNavigate()

  function handleSubmit(e) {
    e.preventDefault()
    if (!username) return
    localStorage.setItem('username', username)
    navigate('/')
  }

  return (
    <div>
      <h2>Login</h2>
      <form onSubmit={handleSubmit}>
        <label>
          Username
          <input value={username} onChange={(e) => setUsername(e.target.value)} placeholder="your name" />
        </label>
        <div style={{ marginTop: 8 }}>
          <button type="submit" className="btn">Sign in</button>
          <Link to="/signup" style={{ marginLeft: 8 }} className="btn secondary">Create account</Link>
        </div>
      </form>
    </div>
  )
}
