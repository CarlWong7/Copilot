import React from 'react'
import { Link, Outlet } from 'react-router-dom'

export default function App() {
  return (
    <div className="app">
      <header style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <h1 style={{ margin: 0 }}>My App</h1>
        <nav className="nav-links">
          <Link to="/">Home</Link>
          <Link to="/login">Login</Link>
          <Link to="/signup">Sign Up</Link>
        </nav>
      </header>
      <main style={{ marginTop: 16 }}>
        <Outlet />
      </main>
    </div>
  )
}
