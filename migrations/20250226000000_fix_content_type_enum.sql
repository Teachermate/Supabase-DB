-- Drop the existing content_type enum and recreate it with the correct values
ALTER TABLE public.content ALTER COLUMN type TYPE text;

DROP TYPE content_type;

CREATE TYPE content_type AS ENUM ('lesson_plan', 'quiz', 'worksheet', 'presentation', 'assessment', 'pedagogy');

ALTER TABLE public.content ALTER COLUMN type TYPE content_type USING type::content_type; 