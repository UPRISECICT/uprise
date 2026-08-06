// Required by firebase_messaging's web plugin so background/closed-tab
// browser notifications can be shown — it auto-registers this exact
// filename at the site root. Values below match lib/firebase_options.dart's
// `web` FirebaseOptions; keep them in sync if that ever changes.
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyC-jZ7dqgbb28y6uK-RnyHYk9PdD9Ta5D0',
  appId: '1:338888794484:web:a8b4900e45844ffeff0c21',
  messagingSenderId: '338888794484',
  projectId: 'uprise-5eac8',
  authDomain: 'uprise-5eac8.firebaseapp.com',
  storageBucket: 'uprise-5eac8.firebasestorage.app',
});

firebase.messaging();
