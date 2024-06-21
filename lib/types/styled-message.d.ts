export type StyledMessage = StyledMessagePart[];

export type StyledMessagePart = string | FormattedString;

type FormattedString = {
  string: string;
  href?: string;
  color?: string;
};
