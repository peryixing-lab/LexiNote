import React from 'react';
import { createRoot } from 'react-dom/client';
import { AppProvider } from './store/AppStore';
import { PluginHostProvider } from './plugins/PluginHostController';
import { App } from './App';
import './styles.css';

const container = document.getElementById('root');
if (!container) throw new Error('Root container missing');

createRoot(container).render(
  <React.StrictMode>
    <AppProvider>
      <PluginHostProvider>
        <App />
      </PluginHostProvider>
    </AppProvider>
  </React.StrictMode>
);
