import React, { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'

export default function Home() {
  const [username, setUsername] = useState(null)
  const navigate = useNavigate()

  useEffect(() => {
    const name = localStorage.getItem('username')
    setUsername(name)
  }, [])

  function signOut() {
    localStorage.removeItem('username')
    setUsername(null)
    navigate('/login')
  }

  return (
    <div>
      <h2>Home</h2>
      {username ? (
        <div>
          <p>Welcome back, <strong>{username}</strong>!</p>
          <button onClick={signOut} className="btn">Sign out</button>
        </div>
      ) : (
        <p>
          You are not signed in. <Link to="/login">Sign in</Link>
        </p>
      )}
    </div>
  )
}
