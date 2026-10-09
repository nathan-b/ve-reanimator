require 'reanimator/gtk_loader'

# Require this instead of 'gtk3' so the harmless PangoCairo warning stays off the console.
Reanimator::GtkLoader.quietly { require 'gtk3' }
