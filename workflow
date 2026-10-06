              nk branch
                 │
                 │ push code
                 ▼
          GitHub Actions
                 │
        ┌────────┴────────┐
        ▼                 ▼
   Flutter Test       Flutter Build
        │
        ▼
      Docker
        │
        ▼
   Docker Hub
        │
        ▼
   Kubernetes image
                 │
                 │
                 ▼
          Pull Request
          nk → main
                 │
              Review
                 │
                 ▼
              MERGE
                 │
                 ▼
              main
